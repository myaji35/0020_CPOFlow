# Org Chart Design

**Feature**: org-chart
**Date**: 2026-02-21
**Phase**: Design
**Task**: #31

---

## 1. 데이터베이스 스키마

### 1-1. countries (신규)

```sql
create_table :countries do |t|
  t.string :code,   null: false              -- "AE", "KR", "SA"
  t.string :name,   null: false              -- "UAE", "한국", "사우디아라비아"
  t.string :name_en, null: false             -- "United Arab Emirates"
  t.string :region                           -- "Middle East", "Asia"
  t.string :flag_emoji                       -- "🇦🇪"
  t.integer :sort_order, default: 0
  t.timestamps
end
add_index :countries, :code, unique: true
```

### 1-2. companies (신규)

```sql
create_table :companies do |t|
  t.references :country, null: false, foreign_key: true
  t.string :name,        null: false          -- "Gagahoho UAE LLC"
  t.string :name_en                           -- 영문 법인명
  t.string :company_type, default: "branch"   -- "hq" / "branch" / "site_office"
  t.string :registration_number               -- 사업자등록번호
  t.string :address
  t.boolean :active, default: true
  t.timestamps
end
add_index :companies, [:country_id, :name]
```

### 1-3. departments (신규)

```sql
create_table :departments do |t|
  t.references :company, null: false, foreign_key: true
  t.integer :parent_id                        -- 상위 부서 (self-referential, nullable)
  t.string :name,    null: false              -- "Engineering"
  t.string :code                             -- "ENG"
  t.integer :sort_order, default: 0
  t.boolean :active, default: true
  t.timestamps
end
add_index :departments, [:company_id, :name]
add_index :departments, :parent_id
```

### 1-4. employees 테이블 수정 (컬럼 추가)

```sql
add_reference :employees, :department, foreign_key: true, null: true
-- 기존 string :department 컬럼은 유지 (점진적 마이그레이션)
```

### 1-5. users 테이블 수정 (컬럼 추가)

```sql
add_reference :users, :company, foreign_key: true, null: true
-- 기존 string :branch enum은 유지 (호환성)
```

---

## 2. 모델

### 2-1. Country

```ruby
class Country < ApplicationRecord
  has_many :companies, dependent: :destroy

  REGIONS = %w[Middle\ East Asia Pacific Europe Americas Africa].freeze

  validates :code, :name, :name_en, presence: true
  validates :code, uniqueness: true, length: { is: 2 }

  scope :by_sort,   -> { order(:sort_order, :name) }
  scope :with_tree, -> { includes(companies: { departments: :employees }) }

  def employee_count
    Employee.joins(department: :company).where(companies: { country_id: id }).count
  end
end
```

### 2-2. Company

```ruby
class Company < ApplicationRecord
  belongs_to :country
  has_many :departments, dependent: :destroy
  has_many :employees, through: :departments
  has_many :users

  COMPANY_TYPES = {
    "hq"          => "본사",
    "branch"      => "지사",
    "site_office" => "현장법인"
  }.freeze

  validates :name, :company_type, presence: true
  validates :company_type, inclusion: { in: COMPANY_TYPES.keys }

  scope :active,   -> { where(active: true) }
  scope :by_name,  -> { order(:name) }

  def company_type_label = COMPANY_TYPES[company_type] || company_type
  def employee_count     = employees.count
end
```

### 2-3. Department

```ruby
class Department < ApplicationRecord
  belongs_to :company
  belongs_to :parent, class_name: "Department", optional: true
  has_many :sub_departments, class_name: "Department", foreign_key: :parent_id, dependent: :nullify
  has_many :employees, foreign_key: :department_id, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :company_id }

  scope :active,      -> { where(active: true) }
  scope :root_level,  -> { where(parent_id: nil) }
  scope :by_sort,     -> { order(:sort_order, :name) }

  def full_name = parent ? "#{parent.name} > #{name}" : name
  def employee_count = employees.active.count
end
```

### 2-4. Employee 수정

```ruby
# 추가
belongs_to :department, optional: true

# 기존 department string 컬럼은 유지
```

### 2-5. User 수정

```ruby
# 추가
belongs_to :company, optional: true
```

---

## 3. 컨트롤러

### 3-1. OrgChartController (메인 트리 뷰)

```ruby
class OrgChartController < ApplicationController
  def index
    @countries = Country.with_tree.by_sort
    @selected_country = Country.find_by(code: params[:country] || "AE")
    @companies = @selected_country&.companies&.active&.includes(departments: :employees) || Company.none
  end
end
```

### 3-2. OrgChart::CountriesController

```ruby
module OrgChart
  class CountriesController < ApplicationController
    before_action :require_admin!
    before_action :set_country, only: %i[show edit update destroy]

    # index, show, new, create, edit, update, destroy
    # 표준 CRUD — 생략
  end
end
```

### 3-3. OrgChart::CompaniesController

```ruby
module OrgChart
  class CompaniesController < ApplicationController
    before_action :require_manager!
    before_action :set_company, only: %i[show edit update destroy]

    def index
      @companies = Company.active.includes(:country, :departments).by_name
    end

    def show
      @departments = @company.departments.active.root_level.includes(:sub_departments, :employees).by_sort
      @employee_count = @company.employee_count
    end
    # new, create, edit, update, destroy — 표준
  end
end
```

### 3-4. OrgChart::DepartmentsController

```ruby
module OrgChart
  class DepartmentsController < ApplicationController
    before_action :set_company
    before_action :require_manager!
    before_action :set_department, only: %i[show edit update destroy]

    def show
      @employees = @department.employees.active.includes(:visas).by_name
    end
    # 표준 CRUD
  end
end
```

---

## 4. 라우트

```ruby
# 조직도 (Org Chart)
get "org_chart", to: "org_chart#index", as: :org_chart

namespace :org_chart do
  resources :countries
  resources :companies do
    resources :departments do
      member { get :employees }
    end
  end
end
```

---

## 5. 뷰 설계

### 5-1. org_chart/index.html.erb — Tree Chart 메인

```
┌─────────────────────────────────────────────┐
│  조직도                    [+ 법인 추가]     │
│  ─────────────────────────────────────────  │
│  [UAE] [Korea] [Saudi]  ← 국가 탭           │
│                                             │
│  Gagahoho UAE LLC  (site_office) [▼]       │
│  └── Engineering (3명)  [▶]                │
│      ├── 김민준  Mechanical Engineer        │
│      ├── Ravi Kumar  Civil Engineer         │
│      └── ...                               │
│  └── Procurement (2명)  [▶]               │
│  └── HR (1명)  [▶]                        │
│                                             │
│  Gagahoho Korea HQ  (hq) [▼]              │
│  └── 경영기획 (2명)                         │
└─────────────────────────────────────────────┘
```

**Alpine.js 구조:**
```html
<div x-data="{ openCompanies: [], openDepts: [] }">
  <!-- 국가 탭 -->
  <!-- 법인 카드 (클릭시 toggle) -->
  <!-- 부서 row (클릭시 toggle) -->
  <!-- 직원 아바타 목록 -->
</div>
```

### 5-2. org_chart/companies/show.html.erb

- 법인 기본정보 카드
- 부서 트리 (root_level 부서 → sub_departments)
- 직원 현황 통계 (전체/투입중/비자만료임박)

### 5-3. org_chart/companies/_form.html.erb

- 법인명(한/영), 법인 유형, 국가 선택, 주소, 사업자번호

### 5-4. org_chart/companies/departments/show.html.erb

- 부서명, 소속 법인
- 직원 카드 목록: 아바타 원형 + 이름 + 직함 + 국적 배지 + 비자 상태

---

## 6. MenuPermission 연동

`MenuPermission::MENU_KEYS`에 `"org_chart"` 추가:

```ruby
MENU_KEYS = %w[orders clients suppliers projects employees org_chart inbox kanban admin].freeze
```

Seeds에 org_chart 권한 기본값 추가 (9번째 메뉴):
```ruby
{ viewer: read-only, member: read-only, manager: CRUD, admin: CRUD }
```

---

## 7. Sidebar 업데이트

```erb
<%# 직원 관리 밑에 추가 %>
<%= nav_link_to org_chart_path, icon: "lni-network", label: "조직도" %>
```

---

## 8. Seeds 샘플 데이터

```ruby
# Countries
ae = Country.create!(code: "AE", name: "UAE", name_en: "United Arab Emirates", region: "Middle East", flag_emoji: "🇦🇪", sort_order: 1)
kr = Country.create!(code: "KR", name: "한국", name_en: "South Korea", region: "Asia", flag_emoji: "🇰🇷", sort_order: 2)

# Companies
uae_co = Company.create!(country: ae, name: "Gagahoho UAE LLC", company_type: "site_office")
kr_co  = Company.create!(country: kr, name: "가가호호 주식회사",  company_type: "hq")

# Departments
eng  = Department.create!(company: uae_co, name: "Engineering",  code: "ENG", sort_order: 1)
proc = Department.create!(company: uae_co, name: "Procurement",  code: "PRO", sort_order: 2)
hr   = Department.create!(company: uae_co, name: "HR",           code: "HR",  sort_order: 3)
mgmt = Department.create!(company: kr_co,  name: "경영기획",      code: "MGT", sort_order: 1)

# Employee → Department 배속
Employee.find_by(name: "김민준")&.update(department_id: hr.id)
Employee.find_by(name: "Muhammad Arif")&.update(department_id: eng.id)
Employee.find_by(name: "Ravi Kumar")&.update(department_id: eng.id)
```

---

## 9. 마이그레이션 순서

1. `create_countries`
2. `create_companies`
3. `create_departments`
4. `add_department_id_to_employees`
5. `add_company_id_to_users`

---

## 10. 구현 체크리스트

- [ ] 마이그레이션 5개 생성 및 실행
- [ ] Country, Company, Department 모델 생성
- [ ] Employee, User 모델 수정 (belongs_to 추가)
- [ ] OrgChartController + 3개 namespace 컨트롤러
- [ ] routes.rb 업데이트
- [ ] org_chart/index Tree Chart 뷰 (Alpine.js)
- [ ] org_chart/companies/ CRUD 뷰
- [ ] org_chart/companies/departments/ CRUD 뷰
- [ ] MenuPermission::MENU_KEYS에 "org_chart" 추가
- [ ] Sidebar nav_link 추가
- [ ] Seeds 업데이트
