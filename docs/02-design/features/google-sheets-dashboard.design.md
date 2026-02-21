# Feature Design: google-sheets-dashboard

**Feature Name**: Google Sheets 대시보드 연동
**Created**: 2026-02-21
**Phase**: Design

---

## 아키텍처 개요

```
[CPOFlow Rails App]
        │
        ▼
[SheetsService]  ←── Service Account JSON (credentials.yml.enc)
        │
        ▼
[Google Sheets API v4]
        │
        ▼
[Spreadsheet]
  ├── 시트1: 발주 현황
  ├── 시트2: 현장 현황
  ├── 시트3: 직원 현황
  └── 시트4: 비자 만료 현황
```

인증: **Service Account** (사용자 OAuth 불필요, 서버→서버)
Gem 추가: `google-apis-sheets_v4` (기존 `googleauth` 재사용)

---

## 1. Gem 추가

```ruby
# Gemfile에 추가
gem "google-apis-sheets_v4"
```

---

## 2. DB 마이그레이션

### sheets_sync_logs 테이블

```ruby
create_table :sheets_sync_logs do |t|
  t.string  :status,        null: false, default: "pending"  # pending/success/failed
  t.string  :spreadsheet_id
  t.integer :orders_count,    default: 0
  t.integer :projects_count,  default: 0
  t.integer :employees_count, default: 0
  t.integer :visas_count,     default: 0
  t.text    :error_message
  t.datetime :synced_at
  t.timestamps
end
```

---

## 3. 모델

### SheetsSyncLog

```ruby
class SheetsSyncLog < ApplicationRecord
  STATUSES = %w[pending success failed].freeze
  validates :status, inclusion: { in: STATUSES }
  scope :recent, -> { order(created_at: :desc).limit(10) }

  def success? = status == "success"
  def failed?  = status == "failed"
end
```

---

## 4. Service

### app/services/sheets/sheets_service.rb

```ruby
module Sheets
  class SheetsService
    SPREADSHEET_ID = Rails.application.credentials.dig(:google, :sheets_spreadsheet_id)

    def initialize
      @service = build_client
    end

    def sync_all
      log = SheetsSyncLog.create!(status: "pending", spreadsheet_id: SPREADSHEET_ID)

      sync_orders(log)
      sync_projects(log)
      sync_employees(log)
      sync_visas(log)

      log.update!(status: "success", synced_at: Time.current)
      log
    rescue => e
      log&.update!(status: "failed", error_message: e.message)
      raise
    end

    private

    def build_client
      # Service Account JSON from credentials
      key_hash = Rails.application.credentials.dig(:google, :service_account)
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(key_hash.to_json),
        scope: "https://www.googleapis.com/auth/spreadsheets"
      )
      svc = Google::Apis::SheetsV4::SheetsService.new
      svc.authorization = credentials
      svc
    end

    def update_sheet(sheet_name, headers, rows)
      values = [headers] + rows
      range  = "#{sheet_name}!A1"
      body   = Google::Apis::SheetsV4::ValueRange.new(values: values)
      @service.update_spreadsheet_value(
        SPREADSHEET_ID, range, body,
        value_input_option: "USER_ENTERED"
      )
    end

    def sync_orders(log)
      headers = ["ID", "제목", "고객사", "상태", "우선순위", "납기일", "견적가", "통화", "생성일"]
      rows = Order.includes(:client).order(created_at: :desc).limit(500).map do |o|
        [o.id, o.title, o.client&.name, o.status, o.priority,
         o.due_date&.strftime("%Y-%m-%d"), o.estimated_value, o.currency,
         o.created_at.strftime("%Y-%m-%d")]
      end
      update_sheet("발주현황", headers, rows)
      log.update!(orders_count: rows.size)
    end

    def sync_projects(log)
      headers = ["ID", "현장명", "코드", "발주처", "국가", "상태", "예산", "통화", "시작일", "종료일"]
      rows = Project.includes(:client).order(created_at: :desc).map do |p|
        [p.id, p.name, p.code, p.client&.name, p.country, p.status,
         p.budget, p.currency,
         p.start_date&.strftime("%Y-%m-%d"), p.end_date&.strftime("%Y-%m-%d")]
      end
      update_sheet("현장현황", headers, rows)
      log.update!(projects_count: rows.size)
    end

    def sync_employees(log)
      headers = ["ID", "이름", "국적", "직책", "부서", "고용형태", "입사일", "상태"]
      rows = Employee.includes(:department).order(:name).map do |e|
        [e.id, e.name, e.nationality, e.job_title, e.department&.name,
         e.employment_type, e.hire_date&.strftime("%Y-%m-%d"),
         e.active? ? "재직" : "퇴직"]
      end
      update_sheet("직원현황", headers, rows)
      log.update!(employees_count: rows.size)
    end

    def sync_visas(log)
      headers = ["직원명", "비자유형", "발급국", "비자번호", "만료일", "D-Day", "상태"]
      rows = Visa.includes(:employee)
                 .where(status: "active")
                 .order(:expiry_date)
                 .map do |v|
        days = (v.expiry_date - Date.today).to_i rescue "N/A"
        [v.employee&.name, v.visa_type, v.issuing_country, v.visa_number,
         v.expiry_date&.strftime("%Y-%m-%d"), days, v.status]
      end
      update_sheet("비자만료현황", headers, rows)
      log.update!(visas_count: rows.size)
    end
  end
end
```

---

## 5. Job

### app/jobs/sheets_sync_job.rb

```ruby
class SheetsSyncJob < ApplicationJob
  queue_as :default

  def perform
    Sheets::SheetsService.new.sync_all
  rescue => e
    Rails.logger.error "[SheetsSyncJob] failed: #{e.message}"
  end
end
```

---

## 6. Controller

### DashboardController 수정

```ruby
# 기존 index 액션에 추가
def index
  # ... 기존 코드 유지 ...
  @last_sync = SheetsSyncLog.recent.first
end

# 신규 액션 추가
def sync_sheets
  SheetsSyncJob.perform_later
  redirect_to dashboard_path, notice: "Google Sheets 동기화가 시작되었습니다."
end
```

### routes.rb 추가

```ruby
get  "dashboard",      to: "dashboard#index"
post "dashboard/sync", to: "dashboard#sync_sheets", as: :sync_sheets
```

---

## 7. 뷰

### dashboard/index.html.erb 추가 (하단 Sheets 섹션)

```erb
<%# Google Sheets 동기화 카드 %>
<div class="bg-white rounded-xl border border-gray-200 p-5 mt-6">
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-lg bg-green-50 flex items-center justify-center">
        <svg class="w-5 h-5 text-green-600" ...><!-- Sheets 아이콘 --></svg>
      </div>
      <div>
        <p class="text-sm font-semibold text-gray-900">Google Sheets 대시보드</p>
        <% if @last_sync %>
          <p class="text-xs text-gray-400">
            마지막 동기화: <%= @last_sync.synced_at&.strftime("%Y-%m-%d %H:%M") || "진행중" %>
            · 발주 <%= @last_sync.orders_count %>건
            · 직원 <%= @last_sync.employees_count %>명
          </p>
        <% else %>
          <p class="text-xs text-gray-400">아직 동기화 기록이 없습니다.</p>
        <% end %>
      </div>
    </div>
    <%= button_to sync_sheets_path, method: :post,
        class: "inline-flex items-center gap-1.5 px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition-colors" do %>
      <svg class="w-4 h-4" ...><!-- 동기화 아이콘 --></svg>
      지금 동기화
    <% end %>
  </div>

  <% if @last_sync&.failed? %>
    <div class="mt-3 px-3 py-2 bg-red-50 rounded-lg text-xs text-red-600">
      오류: <%= @last_sync.error_message %>
    </div>
  <% end %>
</div>
```

---

## 8. Credentials 구조

```yaml
# config/credentials.yml.enc (편집: bin/rails credentials:edit)
google:
  client_id: "..."
  client_secret: "..."
  sheets_spreadsheet_id: "1BxiM..."   # ← 새로 추가
  service_account:                     # ← 새로 추가
    type: "service_account"
    project_id: "..."
    private_key_id: "..."
    private_key: "-----BEGIN RSA PRIVATE KEY-----\n..."
    client_email: "cpoflow@project.iam.gserviceaccount.com"
    token_uri: "https://oauth2.googleapis.com/token"
```

---

## 9. 구현 순서

1. `Gemfile` — `google-apis-sheets_v4` 추가 + bundle install
2. Migration — `sheets_sync_logs` 테이블 생성
3. Model — `SheetsSyncLog`
4. Service — `Sheets::SheetsService`
5. Job — `SheetsSyncJob`
6. Controller — `DashboardController#sync_sheets` + `@last_sync`
7. Routes — `post "dashboard/sync"`
8. View — 대시보드 Sheets 섹션 추가
9. Credentials — `sheets_spreadsheet_id` + `service_account` JSON 등록

---

## 10. 시트별 데이터 명세

| 시트명 | 레코드 수 | 주요 컬럼 |
|--------|----------|----------|
| 발주현황 | Order (최대 500) | ID, 제목, 고객사, 상태, 납기일, 견적가 |
| 현장현황 | Project (전체) | ID, 현장명, 발주처, 국가, 예산, 기간 |
| 직원현황 | Employee (전체) | ID, 이름, 국적, 직책, 부서, 재직여부 |
| 비자만료현황 | Visa (active) | 직원명, 비자유형, 만료일, D-Day |
