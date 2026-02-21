# HR System Design

**Feature**: hr-system
**Date**: 2026-02-21
**Phase**: Design (Completed)

---

## 1. 데이터베이스 스키마

### employees
| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | bigint PK | |
| user_id | bigint FK | 연결된 User (nullable) |
| name | string NOT NULL | 한국어 이름 |
| name_en | string | 영문 이름 |
| nationality | string DEFAULT 'KR' | 국적 코드 |
| passport_number | string | 여권번호 |
| date_of_birth | date | 생년월일 |
| phone | string | 연락처 |
| emergency_contact | string | 비상연락처 이름 |
| emergency_phone | string | 비상연락처 번호 |
| department | string | 부서 |
| job_title | string | 직함 |
| employment_type | string DEFAULT 'regular' | 고용형태 |
| hire_date | date | 입사일 |
| termination_date | date | 퇴사일 |
| active | boolean DEFAULT true | 재직 여부 |
| notes | text | 메모 |

### visas
| 컬럼 | 타입 | 설명 |
|------|------|------|
| employee_id | bigint FK NOT NULL | |
| visa_type | string NOT NULL | Employment/Tourist/Transit/Residence |
| issuing_country | string NOT NULL | 발급국 |
| visa_number | string | 비자 번호 |
| issue_date | date | 발급일 |
| expiry_date | date NOT NULL | 만료일 |
| status | string DEFAULT 'active' | active/expired/pending/cancelled |

### employment_contracts
| 컬럼 | 타입 | 설명 |
|------|------|------|
| employee_id | bigint FK NOT NULL | |
| project_id | bigint FK | 연결 프로젝트 |
| start_date | date NOT NULL | 계약 시작일 |
| end_date | date | 계약 종료일 |
| base_salary | decimal(12,2) | 기본급 |
| currency | string DEFAULT 'USD' | 통화 |
| pay_frequency | string DEFAULT 'monthly' | 지급 주기 |
| status | string DEFAULT 'active' | 계약 상태 |

### employee_assignments
| 컬럼 | 타입 | 설명 |
|------|------|------|
| employee_id | bigint FK NOT NULL | |
| project_id | bigint FK NOT NULL | |
| role | string | 역할 |
| start_date | date NOT NULL | 배정 시작일 |
| end_date | date | 배정 종료일 |
| status | string DEFAULT 'active' | 배정 상태 |

### certifications
| 컬럼 | 타입 | 설명 |
|------|------|------|
| employee_id | bigint FK NOT NULL | |
| name | string NOT NULL | 자격증명 |
| issuing_body | string | 발급기관 |
| issued_date | date | 발급일 |
| expiry_date | date | 만료일 |

### menu_permissions
| 컬럼 | 타입 | 설명 |
|------|------|------|
| role | string NOT NULL | viewer/member/manager/admin |
| menu_key | string NOT NULL | orders/clients/suppliers/projects/employees/inbox/kanban/admin |
| can_read | boolean DEFAULT true | |
| can_create | boolean DEFAULT false | |
| can_update | boolean DEFAULT false | |
| can_delete | boolean DEFAULT false | |

---

## 2. 모델

### Employee
```ruby
EMPLOYMENT_TYPES = %w[regular contract dispatch intern].freeze
NATIONALITIES    = %w[KR PK IN BD PH VN TH].freeze

belongs_to :user, optional: true
has_many :visas, dependent: :destroy
has_many :employment_contracts, dependent: :destroy
has_many :employee_assignments, dependent: :destroy
has_many :projects, through: :employee_assignments
has_many :certifications, dependent: :destroy
```

### Visa
```ruby
VISA_TYPES    = %w[Employment Tourist Transit Residence].freeze
VISA_STATUSES = %w[active expired pending cancelled].freeze

validates :visa_type, inclusion: { in: VISA_TYPES }
validates :status, inclusion: { in: VISA_STATUSES }

def expiry_urgency  # :expired / :critical / :warning / :caution / :normal
def days_until_expiry
```

### MenuPermission
```ruby
ROLES     = %w[viewer member manager admin].freeze
MENU_KEYS = %w[orders clients suppliers projects employees inbox kanban admin].freeze

DEFAULT_PERMISSIONS = {
  "viewer"  => { can_read: true,  can_create: false, can_update: false, can_delete: false },
  "member"  => { can_read: true,  can_create: true,  can_update: true,  can_delete: false },
  "manager" => { can_read: true,  can_create: true,  can_update: true,  can_delete: true  },
  "admin"   => { can_read: true,  can_create: true,  can_update: true,  can_delete: true  }
}.freeze
```

---

## 3. 컨트롤러

- `EmployeesController`: full CRUD + 검색/필터 + 통계
- `VisasController`: nested under employees
- `EmploymentContractsController`: nested under employees
- `EmployeeAssignmentsController`: nested under employees
- `CertificationsController`: nested under employees
- `Settings::MenuPermissionsController`: index, update_all

### ApplicationController 헬퍼
```ruby
def can_read?(menu_key)   # admin 또는 MenuPermission 조회
def can_create?(menu_key)
def can_update?(menu_key)
def can_delete?(menu_key)
helper_method :can_read?, :can_create?, :can_update?, :can_delete?
```

---

## 4. 라우트

```ruby
resources :employees do
  resources :visas,                only: %i[new create edit update destroy]
  resources :employment_contracts, only: %i[new create edit update destroy]
  resources :employee_assignments, only: %i[new create edit update destroy]
  resources :certifications,       only: %i[new create edit update destroy]
end

namespace :settings do
  get  "menu_permissions",  to: "menu_permissions#index"
  patch "menu_permissions", to: "menu_permissions#update_all"
end
```

---

## 5. HrExpiryNotificationJob

```ruby
VISA_TRIGGER_DAYS     = [60, 30, 14].freeze
CONTRACT_TRIGGER_DAYS = [30, 14].freeze

# config/recurring.yml
# hr_expiry_notifications:
#   class: HrExpiryNotificationJob
#   schedule: every day at 8am
```

---

## 6. 뷰 설계

### employees/index
- 통계 카드: 전체/현장투입/비자만료임박/계약만료임박
- 검색/필터: 이름, 부서, 고용형태, 투입중, 비활성 포함

### employees/show (Alpine.js 5탭)
- 기본정보 탭: 연락처, 고용정보, 민감정보(매니저+)
- 비자 탭: 만료 배지 + 상세
- 계약 탭: 급여(매니저+), 계약기간
- 현장배정 탭: 프로젝트 이력
- 자격증 탭: 만료 상태

### settings/menu_permissions/index
- 역할 탭 (viewer/member/manager/admin)
- CRUD 체크박스 매트릭스 (8개 메뉴 × 4개 권한)
