# Design: contact-person-management

**Feature**: 외부 담당자(Contact Person) 관리 강화
**Date**: 2026-03-01
**Phase**: Design
**Based on**: `docs/01-plan/features/contact-person-management.plan.md`

---

## 1. 현재 코드베이스 분석

### 1-1. 기존 DB 스키마 (`contact_persons` 테이블)

```
contactable_id     integer  NOT NULL  -- 폴리모픽 FK
contactable_type   string   NOT NULL  -- "Client" or "Supplier"
name               string
title              string   -- 직책
email              string
phone              string   -- 현재: 유일한 전화 필드 (사무실+모바일 혼용)
whatsapp           string
wechat             string
language           string
nationality        string
primary            boolean  default: false
notes              text
```

**없는 필드**: `mobile`, `department`, `linkedin`, `timezone`, `last_contacted_at`, `source`

### 1-2. 기존 라우트

```ruby
# 현재: clients/suppliers 하위에만 중첩
resources :clients do
  resources :contact_persons, only: %i[new create edit update destroy]
end
resources :suppliers, except: [:destroy] do
  resources :contact_persons, only: %i[new create edit update destroy]
end
# → /contacts 독립 라우트 없음
# → index 액션 없음
```

### 1-3. 기존 컨트롤러 (`app/controllers/contact_persons_controller.rb`)

- 존재하는 액션: `new`, `create`, `edit`, `update`, `destroy`
- **없는 액션**: `index` (전체 목록)
- `set_contactable`: `client_id` 또는 `supplier_id` params로 분기

### 1-4. 기존 모델 (`app/models/contact_person.rb`)

```ruby
class ContactPerson < ApplicationRecord
  belongs_to :contactable, polymorphic: true
  LANGUAGES = { "en" => "English", "ko" => "한국어", "ar" => "العربية", ... }
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  scope :primary_first, -> { order(primary: :desc, name: :asc) }
end
```

### 1-5. 기존 뷰 패턴

- **Supplier/Client 상세 페이지**: Alpine.js 탭 전환, 담당자 루프
- **담당자 추가 버튼**: `link_to new_supplier_contact_person_path` → **새 페이지로 이동** (인라인 아님)
- **수정/삭제**: 새 페이지 이동 방식 (Turbo Frame 미사용)
- **현재 표시 필드**: 이름, 직책, 언어, 이메일/전화/WhatsApp 아이콘 버튼

---

## 2. DB 마이그레이션 설계

### 2-1. 신규 컬럼 추가

```ruby
# db/migrate/YYYYMMDD_add_fields_to_contact_persons.rb
class AddFieldsToContactPersons < ActiveRecord::Migration[8.1]
  def change
    add_column :contact_persons, :mobile,            :string
    add_column :contact_persons, :department,        :string
    add_column :contact_persons, :linkedin,          :string
    add_column :contact_persons, :last_contacted_at, :datetime
    add_column :contact_persons, :source,            :string, default: "manual"

    add_index :contact_persons, :department
    add_index :contact_persons, :last_contacted_at
  end
end
```

**주의**: `timezone`은 Plan에 포함되었으나 MVP에서 제외. 현재 앱에 timezone 처리 인프라 없음.

### 2-2. 마이그레이션 후 스키마 전체

```
contact_persons
  id                   integer PK
  contactable_id       integer NOT NULL
  contactable_type     string  NOT NULL
  name                 string  NOT NULL
  title                string              -- 직책
  email                string
  phone                string              -- 사무실 전화
  mobile               string  [신규]      -- 모바일 번호
  whatsapp             string
  wechat               string
  linkedin             string  [신규]      -- LinkedIn URL
  language             string
  nationality          string
  department           string  [신규]      -- Sales/Technical/CS/Procurement/Management
  primary              boolean default: false
  notes                text
  last_contacted_at    datetime [신규]     -- 마지막 이메일 수신 일시
  source               string  [신규] default: "manual"
                                          -- manual / email_signature / import
  created_at           datetime
  updated_at           datetime
```

---

## 3. 모델 설계 (`app/models/contact_person.rb`)

```ruby
class ContactPerson < ApplicationRecord
  belongs_to :contactable, polymorphic: true

  LANGUAGES = { "en" => "English", "ko" => "한국어", "ar" => "العربية",
                "zh" => "中文", "de" => "Deutsch", "fr" => "Français" }.freeze

  DEPARTMENTS = %w[Sales Technical CS Procurement Management Finance Other].freeze

  SOURCES = %w[manual email_signature import].freeze

  # 기존 검증
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # 신규 검증
  validates :source,     inclusion: { in: SOURCES }, allow_blank: true
  validates :department, inclusion: { in: DEPARTMENTS }, allow_blank: true

  # 기존 scope
  scope :primary_first, -> { order(primary: :desc, name: :asc) }

  # 신규 scope
  scope :with_contactable, -> { includes(:contactable) }
  scope :recently_contacted, -> { order(last_contacted_at: :desc) }
  scope :by_department, ->(dept) { where(department: dept) if dept.present? }
  scope :for_clients,   -> { where(contactable_type: "Client") }
  scope :for_suppliers, -> { where(contactable_type: "Supplier") }
  scope :primary_only,  -> { where(primary: true) }

  # 전문 검색 scope (LIKE 기반 — SQLite, PostgreSQL 모두 호환)
  scope :search, ->(q) {
    return all if q.blank?
    term = "%#{q.downcase}%"
    where(
      "LOWER(contact_persons.name) LIKE ? OR LOWER(contact_persons.email) LIKE ? " \
      "OR contact_persons.phone LIKE ? OR contact_persons.mobile LIKE ?",
      term, term, term, term
    )
  }

  # 기존 헬퍼 메서드
  def display_name
    primary? ? "★ #{name}" : name
  end

  def language_label
    LANGUAGES[language] || language
  end

  # 신규 헬퍼 메서드
  def contactable_name
    contactable&.name
  end

  def contactable_type_label
    contactable_type == "Client" ? "발주처" : "거래처"
  end

  def last_contacted_label
    return "없음" if last_contacted_at.nil?
    days = ((Time.current - last_contacted_at) / 1.day).round
    case days
    when 0      then "오늘"
    when 1      then "어제"
    when 2..30  then "#{days}일 전"
    else        last_contacted_at.strftime("%Y-%m-%d")
    end
  end
end
```

---

## 4. 라우트 설계 (`config/routes.rb` 수정)

```ruby
# 기존 유지
resources :clients do
  collection { get :search }
  resources :contact_persons, only: %i[new create edit update destroy]
end

resources :suppliers, except: [:destroy] do
  collection { get :search }
  resources :contact_persons, only: %i[new create edit update destroy]
  resources :supplier_products, only: %i[create destroy]
end

# 신규 추가: 전체 담당자 독립 라우트
resources :contact_persons, only: %i[index] do
  # Inbox에서 "담당자로 저장" 액션
  collection do
    post :create_from_signature
  end
end
```

**생성되는 라우트**:
```
GET  /contact_persons                    contact_persons#index
POST /contact_persons/create_from_signature  contact_persons#create_from_signature
```

---

## 5. 컨트롤러 설계

### 5-1. `ContactPersonsController` 수정 (`app/controllers/contact_persons_controller.rb`)

#### `index` 액션 추가

```ruby
def index
  @contact_persons = ContactPerson
    .with_contactable
    .search(params[:q])
    .by_department(params[:department])
    .then { |rel|
      case params[:type]
      when "clients"   then rel.for_clients
      when "suppliers" then rel.for_suppliers
      else rel
      end
    }
    .then { |rel|
      case params[:sort]
      when "recent"   then rel.recently_contacted
      when "company"  then rel.joins("LEFT JOIN clients ON contact_persons.contactable_id = clients.id AND contact_persons.contactable_type = 'Client' LEFT JOIN suppliers ON contact_persons.contactable_id = suppliers.id AND contact_persons.contactable_type = 'Supplier'").order("COALESCE(clients.name, suppliers.name) ASC")
      else rel.primary_first
      end
    }
    .page(params[:page]).per(24)
end
```

**파라미터**:
- `q`: 검색어 (이름/이메일/전화/모바일)
- `type`: `clients` / `suppliers` / 없으면 전체
- `department`: `Sales`, `Technical`, `CS`, `Procurement`, `Management`
- `sort`: `name`(기본) / `recent` / `company`
- `page`: 페이지네이션

#### `create_from_signature` 액션 추가

```ruby
def create_from_signature
  # Inbox 발신처 카드 → "담당자로 저장" 버튼 처리
  @order = Order.find(params[:order_id])
  sig = @order.email_signature_json.present? ? JSON.parse(@order.email_signature_json) : {}

  # contactable 특정: 발신 도메인으로 Client/Supplier 검색
  contactable = find_contactable_by_domain(@order.sender_domain)

  unless contactable
    redirect_to inbox_email_path(@order), alert: "발주처/거래처를 먼저 연결하세요."
    return
  end

  @contact_person = ContactPerson.new(
    contactable: contactable,
    name:        sig["name"].presence || params[:name],
    title:       sig["title"].presence || params[:title],
    email:       sig["email"].presence || @order.original_email_from.to_s.match(/<(.+)>/)&.[](1) || @order.original_email_from,
    phone:       sig["phone"],
    mobile:      sig["mobile"],
    source:      "email_signature"
  )

  if @contact_person.save
    # last_contacted_at 즉시 업데이트
    @contact_person.update_column(:last_contacted_at, @order.created_at)
    redirect_back fallback_location: inbox_email_path(@order),
                  notice: "#{@contact_person.name}이 담당자로 저장되었습니다."
  else
    redirect_back fallback_location: inbox_email_path(@order),
                  alert: @contact_person.errors.full_messages.join(", ")
  end
end
```

#### 기존 `create`, `update` 액션 — strong params 확장

```ruby
def contact_person_params
  params.require(:contact_person).permit(
    :name, :title, :email, :phone,
    :mobile, :department, :linkedin,   # 신규 필드
    :whatsapp, :wechat, :language, :nationality, :primary, :notes
  )
end
```

---

## 6. 뷰 설계

### 6-1. 전체 담당자 목록 페이지 (`app/views/contact_persons/index.html.erb`)

**레이아웃**: 검색 + 필터 헤더 / 카드 그리드 24개씩 페이지네이션

```erb
<div class="flex flex-col gap-6">
  <!-- 페이지 헤더 -->
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">전체 담당자</h1>
      <p class="text-sm text-gray-500 mt-1"><%= @contact_persons.total_count %>명</p>
    </div>
  </div>

  <!-- 검색 + 필터 바 -->
  <%= form_with url: contact_persons_path, method: :get, data: { turbo_frame: "_top" } do |f| %>
    <div class="flex flex-wrap gap-3 items-center">
      <!-- 검색창 -->
      <div class="relative flex-1 min-w-60">
        <svg class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" .../>
        <%= f.text_field :q, value: params[:q], placeholder: "이름, 이메일, 전화번호, 회사 검색...",
            class: "w-full pl-9 pr-4 py-2 text-sm border border-gray-200 rounded-lg ..." %>
      </div>
      <!-- 타입 필터 (발주처/거래처/전체) -->
      <%= f.select :type, [["전체", ""], ["발주처만", "clients"], ["거래처만", "suppliers"]],
          { selected: params[:type] }, class: "text-sm border border-gray-200 rounded-lg ..." %>
      <!-- 부서 필터 -->
      <%= f.select :department,
          [["전체 부서", ""]] + ContactPerson::DEPARTMENTS.map { |d| [d, d] },
          { selected: params[:department] }, class: "..." %>
      <!-- 정렬 -->
      <%= f.select :sort, [["이름순", "name"], ["최근 연락순", "recent"], ["회사명순", "company"]],
          { selected: params[:sort] }, class: "..." %>
    </div>
  <% end %>

  <!-- 카드 그리드 -->
  <% if @contact_persons.empty? %>
    <div class="text-center py-16 text-gray-400 dark:text-gray-500">
      <p class="text-sm">검색 결과가 없습니다.</p>
    </div>
  <% else %>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
      <% @contact_persons.each do |cp| %>
        <%= render "contact_persons/card", contact_person: cp %>
      <% end %>
    </div>
    <!-- 페이지네이션 -->
    <%= paginate @contact_persons %>
  <% end %>
</div>
```

### 6-2. 담당자 카드 partial (`app/views/contact_persons/_card.html.erb`)

```erb
<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-100 dark:border-gray-700
            shadow-sm p-4 hover:border-primary/40 transition-colors">
  <!-- 상단: 아바타 + 이름 + 주 담당자 뱃지 -->
  <div class="flex items-start gap-3 mb-3">
    <div class="w-10 h-10 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center
                justify-center text-blue-700 dark:text-blue-400 font-bold text-sm flex-shrink-0">
      <%= contact_person.name.first(2).upcase %>
    </div>
    <div class="flex-1 min-w-0">
      <div class="flex items-center gap-1.5 flex-wrap">
        <span class="font-semibold text-sm text-gray-900 dark:text-white truncate">
          <%= contact_person.name %>
        </span>
        <% if contact_person.primary? %>
          <span class="text-xs px-1.5 py-0.5 rounded-full bg-yellow-50 dark:bg-yellow-900/20
                       text-yellow-700 dark:text-yellow-400 font-medium">주</span>
        <% end %>
      </div>
      <p class="text-xs text-gray-500 dark:text-gray-400 truncate"><%= contact_person.title %></p>
      <!-- 부서 뱃지 -->
      <% if contact_person.department.present? %>
        <span class="inline-flex mt-1 text-xs px-1.5 py-0.5 rounded-full
                     bg-indigo-50 dark:bg-indigo-900/20 text-indigo-700 dark:text-indigo-400">
          <%= contact_person.department %>
        </span>
      <% end %>
    </div>
  </div>

  <!-- 회사 -->
  <p class="text-xs text-gray-500 dark:text-gray-400 mb-2 truncate">
    <span class="inline-flex px-1.5 py-0.5 rounded text-xs
                 <%= contact_person.contactable_type == 'Client' ?
                     'bg-blue-50 text-blue-700 dark:bg-blue-900/20 dark:text-blue-400' :
                     'bg-purple-50 text-purple-700 dark:bg-purple-900/20 dark:text-purple-400' %>">
      <%= contact_person.contactable_type_label %>
    </span>
    <%= contact_person.contactable_name %>
  </p>

  <!-- 연락 버튼 -->
  <div class="flex items-center gap-1.5 mb-3">
    <% if contact_person.email.present? %>
      <a href="mailto:<%= contact_person.email %>" title="<%= contact_person.email %>"
         class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200
                dark:border-gray-600 text-gray-400 hover:text-primary hover:border-primary transition-colors">
        <!-- email icon SVG -->
      </a>
    <% end %>
    <% if contact_person.phone.present? %>
      <a href="tel:<%= contact_person.phone %>" title="사무실: <%= contact_person.phone %>"
         class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200
                dark:border-gray-600 text-gray-400 hover:text-green-600 hover:border-green-400 transition-colors">
        <!-- phone icon SVG -->
      </a>
    <% end %>
    <% if contact_person.mobile.present? %>
      <a href="tel:<%= contact_person.mobile %>" title="모바일: <%= contact_person.mobile %>"
         class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200
                dark:border-gray-600 text-gray-400 hover:text-blue-600 hover:border-blue-400 transition-colors">
        <!-- smartphone icon SVG -->
      </a>
    <% end %>
    <% if contact_person.whatsapp.present? %>
      <a href="https://wa.me/<%= contact_person.whatsapp.gsub(/\D/, '') %>"
         target="_blank" rel="noopener" title="WhatsApp: <%= contact_person.whatsapp %>"
         class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200
                dark:border-gray-600 text-gray-400 hover:text-green-500 hover:border-green-400 transition-colors">
        <!-- whatsapp icon SVG -->
      </a>
    <% end %>
    <% if contact_person.linkedin.present? %>
      <a href="<%= contact_person.linkedin %>" target="_blank" rel="noopener" title="LinkedIn"
         class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200
                dark:border-gray-600 text-gray-400 hover:text-blue-700 hover:border-blue-400 transition-colors">
        <!-- linkedin icon SVG -->
      </a>
    <% end %>
  </div>

  <!-- 마지막 연락일 -->
  <p class="text-xs text-gray-400 dark:text-gray-500">
    마지막 연락: <%= contact_person.last_contacted_label %>
  </p>
</div>
```

### 6-3. Client/Supplier 상세 담당자 탭 — Turbo Frame 인라인 추가

**현재 방식** (새 페이지 이동):
```erb
<%= link_to new_client_contact_person_path(@client) %>
```

**변경 방식** (Turbo Frame 인라인 슬라이드다운):

```erb
<!-- 담당자 탭 헤더 -->
<div class="flex justify-between items-center mb-4">
  <h3 class="font-medium text-gray-900 dark:text-white">담당자 목록</h3>
  <button onclick="document.getElementById('new-contact-form-<%= @client.id %>').classList.toggle('hidden')"
          class="inline-flex items-center gap-1 text-sm text-primary hover:underline">
    <svg class="w-4 h-4" ...>+</svg>
    담당자 추가
  </button>
</div>

<!-- 인라인 추가 폼 (기본 hidden) -->
<turbo-frame id="new-contact-form-<%= @client.id %>">
  <div id="new-contact-form-<%= @client.id %>" class="hidden mb-4 p-4 border border-primary/20
       rounded-lg bg-blue-50/30 dark:bg-blue-900/10">
    <%= render "contact_persons/inline_form",
               contactable: @client,
               contact_person: ContactPerson.new %>
  </div>
</turbo-frame>

<!-- 담당자 목록 (Turbo Frame으로 래핑 — 새 항목 추가 시 갱신) -->
<turbo-frame id="contact-persons-<%= @client.id %>">
  <div class="space-y-3">
    <% @contact_persons.each do |cp| %>
      <turbo-frame id="contact-person-<%= cp.id %>">
        <%= render "contact_persons/row", contact_person: cp, contactable: @client %>
      </turbo-frame>
    <% end %>
    <% if @contact_persons.empty? %>
      <p class="text-center text-gray-400 text-sm py-8">등록된 담당자가 없습니다.</p>
    <% end %>
  </div>
</turbo-frame>
```

### 6-4. 인라인 폼 partial (`app/views/contact_persons/_inline_form.html.erb`)

```erb
<%= form_with model: [contactable, contact_person],
              data: { turbo_frame: "contact-persons-#{contactable.id}", turbo_action: "advance" } do |f| %>
  <div class="grid grid-cols-2 gap-3 mb-3">
    <div>
      <%= f.label :name, "이름 *", class: "..." %>
      <%= f.text_field :name, required: true, class: "..." %>
    </div>
    <div>
      <%= f.label :title, "직책", class: "..." %>
      <%= f.text_field :title, class: "..." %>
    </div>
    <div>
      <%= f.label :department, "부서", class: "..." %>
      <%= f.select :department, [["선택", ""]] + ContactPerson::DEPARTMENTS.map { |d| [d, d] },
          {}, class: "..." %>
    </div>
    <div>
      <%= f.label :email, "이메일", class: "..." %>
      <%= f.email_field :email, class: "..." %>
    </div>
    <div>
      <%= f.label :phone, "전화(사무실)", class: "..." %>
      <%= f.tel_field :phone, class: "..." %>
    </div>
    <div>
      <%= f.label :mobile, "모바일", class: "..." %>
      <%= f.tel_field :mobile, class: "..." %>
    </div>
    <div>
      <%= f.label :whatsapp, "WhatsApp", class: "..." %>
      <%= f.tel_field :whatsapp, class: "..." %>
    </div>
    <div>
      <%= f.label :language, "언어", class: "..." %>
      <%= f.select :language,
          [["선택", ""]] + ContactPerson::LANGUAGES.map { |code, name| [name, code] },
          {}, class: "..." %>
    </div>
  </div>
  <div class="flex gap-2 justify-end">
    <button type="button"
            onclick="document.getElementById('new-contact-form-<%= contactable.id %>').classList.add('hidden')"
            class="text-sm text-gray-500 px-3 py-1.5 rounded-lg border border-gray-200 hover:bg-gray-50">
      취소
    </button>
    <%= f.submit "저장", class: "text-sm text-white bg-primary px-4 py-1.5 rounded-lg hover:bg-primary/90" %>
  </div>
<% end %>
```

### 6-5. 담당자 행 partial (`app/views/contact_persons/_row.html.erb`)

기존 Client/Supplier 상세 담당자 목록 행 → Turbo Frame 래핑 + 신규 필드 표시

```erb
<div class="flex items-center justify-between p-3 border border-gray-100 dark:border-gray-700
            rounded-lg hover:border-primary/30 transition-colors">
  <div class="flex items-center gap-3">
    <!-- 이니셜 아바타 -->
    <div class="w-9 h-9 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center
                justify-center text-blue-700 dark:text-blue-400 font-bold text-sm">
      <%= contact_person.name.first(2).upcase %>
    </div>
    <div>
      <!-- 이름 + 주 담당자 뱃지 -->
      <div class="flex items-center gap-1.5">
        <span class="font-medium text-sm text-gray-900 dark:text-white">
          <%= contact_person.name %>
        </span>
        <% if contact_person.primary? %>
          <span class="text-xs px-1 py-0.5 rounded bg-yellow-50 text-yellow-700 dark:bg-yellow-900/20 dark:text-yellow-400">주</span>
        <% end %>
      </div>
      <!-- 직책 + 부서 -->
      <div class="flex items-center gap-1.5 mt-0.5">
        <p class="text-xs text-gray-500 dark:text-gray-400"><%= contact_person.title %></p>
        <% if contact_person.department.present? %>
          <span class="text-xs px-1.5 py-0.5 rounded-full bg-indigo-50 dark:bg-indigo-900/20
                       text-indigo-700 dark:text-indigo-400"><%= contact_person.department %></span>
        <% end %>
      </div>
      <!-- 연락 버튼 -->
      <div class="flex items-center gap-1.5 mt-1.5">
        <%# email, phone, mobile, whatsapp 아이콘 버튼 (기존 패턴 유지, mobile 추가) %>
        <% if contact_person.email.present? %>
          <a href="mailto:<%= contact_person.email %>" title="<%= contact_person.email %>"
             class="inline-flex items-center justify-center w-7 h-7 rounded-full border
                    border-gray-200 dark:border-gray-600 text-gray-400 hover:text-primary
                    hover:border-primary transition-colors">
            <!-- email SVG -->
          </a>
        <% end %>
        <% if contact_person.phone.present? %>
          <a href="tel:<%= contact_person.phone %>" title="사무실: <%= contact_person.phone %>"
             class="..."><svg class="w-3.5 h-3.5" ...><!-- phone --></svg></a>
        <% end %>
        <% if contact_person.mobile.present? %>
          <a href="tel:<%= contact_person.mobile %>" title="모바일: <%= contact_person.mobile %>"
             class="... hover:text-blue-600 hover:border-blue-400">
            <svg class="w-3.5 h-3.5" ...><!-- smartphone --></svg>
          </a>
        <% end %>
        <% if contact_person.whatsapp.present? %>
          <a href="https://wa.me/<%= contact_person.whatsapp.gsub(/\D/, '') %>"
             target="_blank" rel="noopener" title="WhatsApp"
             class="... hover:text-green-500 hover:border-green-400">
            <!-- whatsapp SVG -->
          </a>
        <% end %>
      </div>
    </div>
  </div>

  <div class="flex flex-col items-end gap-2">
    <!-- 마지막 연락일 -->
    <% if contact_person.last_contacted_at.present? %>
      <span class="text-xs text-gray-400 dark:text-gray-500">
        <%= contact_person.last_contacted_label %>
      </span>
    <% end %>
    <!-- 수정/삭제 -->
    <div class="flex gap-2">
      <%= link_to edit_contactable_contact_person_path(contactable, contact_person),
          class: "text-xs text-gray-400 hover:text-primary" do %>수정<% end %>
      <%= link_to contactable_contact_person_path(contactable, contact_person),
          data: { turbo_method: :delete, turbo_confirm: "삭제?" },
          class: "text-xs text-gray-400 hover:text-red-500" do %>삭제<% end %>
    </div>
  </div>
</div>
```

**helper method** (`app/helpers/contact_persons_helper.rb`):
```ruby
module ContactPersonsHelper
  def edit_contactable_contact_person_path(contactable, cp)
    if contactable.is_a?(Client)
      edit_client_contact_person_path(contactable, cp)
    else
      edit_supplier_contact_person_path(contactable, cp)
    end
  end

  def contactable_contact_person_path(contactable, cp)
    if contactable.is_a?(Client)
      client_contact_person_path(contactable, cp)
    else
      supplier_contact_person_path(contactable, cp)
    end
  end
end
```

### 6-6. 담당자 폼 (`app/views/contact_persons/_form.html.erb`) 신규 필드 추가

기존 폼에 `mobile`, `department`, `linkedin` 필드 추가:

```erb
<!-- 기존 phone 아래에 추가 -->
<div>
  <%= f.label :mobile, "모바일 번호", class: "..." %>
  <%= f.tel_field :mobile, class: "...", placeholder: "+971-50-000-0000" %>
</div>

<!-- 기존 language/nationality 사이에 추가 -->
<div>
  <%= f.label :department, "부서", class: "..." %>
  <%= f.select :department,
      [["선택", ""]] + ContactPerson::DEPARTMENTS.map { |d| [d, d] },
      { selected: f.object.department }, class: "..." %>
</div>

<!-- 기존 notes 위에 추가 -->
<div>
  <%= f.label :linkedin, "LinkedIn URL", class: "..." %>
  <%= f.url_field :linkedin, class: "...", placeholder: "https://linkedin.com/in/..." %>
</div>
```

---

## 7. Inbox 연동 설계

### 7-1. "담당자로 저장" 버튼 (`app/views/inbox/index.html.erb`)

`email-signature-attachment` 피처의 발신처 카드 UI 내에 버튼 추가 (두 피처 연동):

```erb
<!-- 발신처 카드 하단 (email-signature-attachment.design.md 참조) -->
<% if @selected_order.sender_domain.present? %>
  <div class="mt-3 pt-3 border-t border-gray-100 dark:border-gray-700 flex gap-2">
    <%= button_to create_from_signature_contact_persons_path,
        params: { order_id: @selected_order.id },
        method: :post,
        class: "text-xs px-3 py-1.5 rounded-lg border border-primary text-primary hover:bg-primary/5 transition-colors" do %>
      담당자로 저장
    <% end %>
  </div>
<% end %>
```

### 7-2. `EmailToOrderService` — `last_contacted_at` 자동 업데이트

`app/services/gmail/email_to_order_service.rb`에서 기존 담당자 매칭 시 업데이트:

```ruby
# create_order! 성공 후 호출
def update_contact_person_last_contacted(order)
  from_email = @email[:from].to_s.match(/<(.+)>/)&.[](1) || @email[:from].to_s.strip.downcase
  return if from_email.blank?

  cp = ContactPerson.find_by("LOWER(email) = ?", from_email.downcase)
  cp&.update_column(:last_contacted_at, Time.current)
end
```

`create_order!` 내 `order.save` 성공 블록에:
```ruby
if order.save
  # ... 기존 코드 ...
  update_contact_person_last_contacted(order)
  order
end
```

---

## 8. 좌측 네비게이션 메뉴 추가

`app/views/layouts/_sidebar.html.erb` (또는 네비게이션 partial)에 링크 추가:

```erb
<%= link_to contact_persons_path, class: "nav-item #{current_page?(contact_persons_path) ? 'active' : ''}" do %>
  <svg class="w-5 h-5" ...><!-- users icon --></svg>
  <span>외부 담당자</span>
<% end %>
```

---

## 9. 구현 순서 체크리스트

### Step 1: DB 마이그레이션

- [ ] `db/migrate/YYYYMMDD_add_fields_to_contact_persons.rb` 생성
- [ ] `bin/rails db:migrate` 실행
- [ ] `db/schema.rb` 변경 확인

### Step 2: 모델 업데이트

- [ ] `ContactPerson::DEPARTMENTS`, `ContactPerson::SOURCES` 상수 추가
- [ ] 신규 scope (search, by_department, recently_contacted 등) 추가
- [ ] `last_contacted_label`, `contactable_name` 헬퍼 메서드 추가
- [ ] 신규 검증 추가

### Step 3: 라우트 추가

- [ ] `config/routes.rb`에 `resources :contact_persons, only: %i[index]` 추가
- [ ] `collection { post :create_from_signature }` 추가
- [ ] `bin/rails routes | grep contact_person` 로 확인

### Step 4: 컨트롤러 확장

- [ ] `ContactPersonsController#index` 구현 (검색·필터·정렬·페이지네이션)
- [ ] `ContactPersonsController#create_from_signature` 구현
- [ ] `contact_person_params` strong params에 신규 필드 추가

### Step 5: 전체 목록 뷰

- [ ] `app/views/contact_persons/index.html.erb` 생성
- [ ] `app/views/contact_persons/_card.html.erb` 생성
- [ ] 검색/필터 폼 turbo 연동 확인

### Step 6: 기존 뷰 개선 (Client/Supplier 상세 담당자 탭)

- [ ] `app/views/contact_persons/_row.html.erb` 생성 (mobile, department, last_contacted 포함)
- [ ] `app/views/contact_persons/_inline_form.html.erb` 생성
- [ ] `app/views/clients/show.html.erb` — Turbo Frame 적용
- [ ] `app/views/suppliers/show.html.erb` — Turbo Frame 적용
- [ ] `ContactPersonsController#create` — Turbo Stream 응답 추가

### Step 7: 기존 폼 업데이트

- [ ] `app/views/contact_persons/_form.html.erb`에 mobile, department, linkedin 추가

### Step 8: Inbox 연동

- [ ] `app/views/inbox/index.html.erb` — 발신처 카드에 "담당자로 저장" 버튼 추가
- [ ] `app/services/gmail/email_to_order_service.rb` — `update_contact_person_last_contacted` 추가

### Step 9: 네비게이션

- [ ] 좌측 사이드바에 "외부 담당자" 메뉴 링크 추가

---

## 10. Turbo Stream 응답 패턴 (인라인 추가 핵심)

```ruby
# ContactPersonsController#create (클라이언트/공급업체 상세 내 인라인 추가)
def create
  @contactable = set_contactable
  @contact_person = @contactable.contact_persons.build(contact_person_params)
  @contact_person.source ||= "manual"

  if @contact_person.save
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # 목록에 새 항목 append
          turbo_stream.append("contact-persons-#{@contactable.id}",
            partial: "contact_persons/row",
            locals: { contact_person: @contact_person, contactable: @contactable }),
          # 인라인 폼 초기화
          turbo_stream.replace("new-contact-form-#{@contactable.id}",
            partial: "contact_persons/inline_form",
            locals: { contactable: @contactable, contact_person: ContactPerson.new }),
          # 폼 닫기 (JS)
          turbo_stream.append("flash", "<script>document.getElementById('new-contact-form-#{@contactable.id}').classList.add('hidden')</script>".html_safe)
        ]
      end
      format.html { redirect_back fallback_location: root_path }
    end
  else
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("new-contact-form-#{@contactable.id}", partial: "contact_persons/inline_form", locals: { contactable: @contactable, contact_person: @contact_person }) }
      format.html { render :new }
    end
  end
end
```

---

## 11. 의존성 및 주의사항

### 의존성
- `kaminari` gem — 페이지네이션 (`/contacts` 목록) — 기존 사용 중 확인 필요
- `email-signature-attachment` 피처 — `email_signature_json` 컬럼 필요 (7번 Inbox 연동)

### 주의사항
1. **폴리모픽 경로 헬퍼**: `edit_client_contact_person_path` vs `edit_supplier_contact_person_path` — Helper 메서드로 추상화 필수
2. **기존 뷰 하위호환**: `_row.html.erb` partial로 교체 시 Client/Supplier 양쪽 모두 확인
3. **N+1 방지**: `index` 액션에서 `.with_contactable` (includes) 필수
4. **인라인 폼 ID 충돌 방지**: `contactable.id`를 DOM ID에 포함 (예: `contact-persons-42`)

---

## 12. 관련 파일 목록

### 신규 생성
| 파일 | 역할 |
|------|------|
| `db/migrate/YYYYMMDD_add_fields_to_contact_persons.rb` | DB 마이그레이션 |
| `app/views/contact_persons/index.html.erb` | 전체 담당자 목록 |
| `app/views/contact_persons/_card.html.erb` | 담당자 카드 (목록용) |
| `app/views/contact_persons/_row.html.erb` | 담당자 행 (상세 탭용) |
| `app/views/contact_persons/_inline_form.html.erb` | 인라인 추가 폼 |

### 수정
| 파일 | 변경 내용 |
|------|-----------|
| `app/models/contact_person.rb` | DEPARTMENTS 상수, scope, 헬퍼 메서드 추가 |
| `app/controllers/contact_persons_controller.rb` | index, create_from_signature 추가; create Turbo Stream 응답 |
| `app/views/contact_persons/_form.html.erb` | mobile, department, linkedin 필드 추가 |
| `app/views/clients/show.html.erb` | Turbo Frame 인라인 담당자 탭 |
| `app/views/suppliers/show.html.erb` | 동일 |
| `app/views/inbox/index.html.erb` | "담당자로 저장" 버튼 |
| `config/routes.rb` | /contact_persons 독립 라우트 추가 |
| `app/services/gmail/email_to_order_service.rb` | last_contacted_at 업데이트 |
