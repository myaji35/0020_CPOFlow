# Design: CPOFlow 고도화 7대 기능

**Feature**: cpoflow-enhancement
**작성일**: 2026-02-22
**Phase**: Design
**참조**: docs/01-plan/features/cpoflow-enhancement.plan.md

---

## Feature 1: 견적/발주 PDF 문서 생성기

### DB 변경
없음 (기존 Order 데이터 활용)

### 신규 파일
```
app/controllers/orders/pdf_controller.rb
app/views/orders/pdf/quote.html.erb      # 견적서 템플릿
app/views/orders/pdf/purchase_order.html.erb  # 발주서 템플릿
```

### 라우트
```ruby
resources :orders do
  member do
    get 'pdf/quote',          to: 'orders/pdf#quote'
    get 'pdf/purchase_order', to: 'orders/pdf#purchase_order'
  end
end
```

### 컨트롤러
```ruby
# app/controllers/orders/pdf_controller.rb
class Orders::PdfController < ApplicationController
  before_action :set_order

  def quote
    respond_to do |format|
      format.pdf do
        render pdf: "quote_#{@order.id}",
               template: "orders/pdf/quote",
               layout: "pdf"
      end
    end
  end

  def purchase_order
    respond_to do |format|
      format.pdf do
        render pdf: "po_#{@order.id}",
               template: "orders/pdf/purchase_order",
               layout: "pdf"
      end
    end
  end
end
```

### Gem 추가
```ruby
gem 'wkhtmltopdf-binary'
gem 'wicked_pdf'
```

### 뷰 버튼 (orders/show)
```erb
<%= link_to "견적서 PDF", pdf_quote_order_path(@order, format: :pdf), target: "_blank" %>
<%= link_to "발주서 PDF", pdf_purchase_order_order_path(@order, format: :pdf), target: "_blank" %>
```

---

## Feature 2: 알림 센터 + Google Chat 연동

### DB 변경
```ruby
# migration: create_notifications
create_table :notifications do |t|
  t.references :user, null: false, foreign_key: true
  t.references :notifiable, polymorphic: true
  t.string  :title, null: false
  t.text    :body
  t.string  :notification_type  # due_date / status_changed / assigned / system
  t.datetime :read_at
  t.timestamps
end
add_index :notifications, [:user_id, :read_at]
```

### 신규 파일
```
app/models/notification.rb
app/controllers/notifications_controller.rb
app/views/notifications/_notification.html.erb
app/views/notifications/index.html.erb
app/jobs/notification_delivery_job.rb
app/services/google_chat_service.rb
app/mailers/order_mailer.rb              # 기존 있으면 수정
```

### Google Chat Webhook
```ruby
# app/services/google_chat_service.rb
class GoogleChatService
  WEBHOOK_URL = Rails.application.credentials.dig(:google_chat, :webhook_url)

  def self.notify(message, order: nil)
    return unless WEBHOOK_URL.present?

    payload = { text: message }
    if order
      payload = {
        cards: [{
          header: { title: "CPOFlow 알림", subtitle: order.title },
          sections: [{
            widgets: [
              { textParagraph: { text: message } },
              { buttons: [{ textButton: { text: "주문 보기",
                onClick: { openLink: { url: order_url(order) } } } }] }
            ]
          }]
        }]
      }
    end

    HTTP.post(WEBHOOK_URL, json: payload)
  rescue => e
    Rails.logger.error "[GoogleChat] #{e.message}"
  end
end
```

### Notification 모델
```ruby
# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read!
    update!(read_at: Time.current)
  end
end
```

### 알림 배지 (레이아웃)
```erb
<%# app/views/layouts/_topbar.html.erb 내 알림 버튼 %>
<div data-controller="notifications">
  <button data-action="click->notifications#toggle">
    <svg><!-- bell icon --></svg>
    <% unread = current_user.notifications.unread.count %>
    <% if unread > 0 %>
      <span class="badge"><%= unread %></span>
    <% end %>
  </button>
</div>
```

### NotificationDeliveryJob
```ruby
# 납기 D-7, D-3, D-0 자동 알림
class NotificationDeliveryJob < ApplicationJob
  def perform
    [7, 3, 0].each do |days|
      Order.where(due_date: Date.today + days.days)
           .where.not(status: :delivered)
           .each do |order|
        order.assignees.each do |user|
          next if already_notified?(order, user, days)
          Notification.create!(user: user, notifiable: order,
            title: "납기 D-#{days}: #{order.title}",
            notification_type: "due_date")
          GoogleChatService.notify("⚠️ 납기 D-#{days}: #{order.title}", order: order)
        end
      end
    end
  end
end
```

### 라우트
```ruby
resources :notifications, only: [:index] do
  collection { patch :read_all }
  member     { patch :read }
end
```

---

## Feature 3: 주문 일괄 처리 (Bulk Actions)

### DB 변경
없음

### 신규 파일
```
app/controllers/orders/bulk_controller.rb
app/javascript/controllers/bulk_select_controller.js
```

### 컨트롤러
```ruby
# app/controllers/orders/bulk_controller.rb
class Orders::BulkController < ApplicationController
  before_action :require_manager!

  def update
    orders = Order.where(id: params[:order_ids])
    case params[:action_type]
    when "status"   then orders.update_all(status: params[:status])
    when "priority" then orders.update_all(priority: params[:priority])
    when "assign"   then bulk_assign(orders, params[:user_id])
    end
    redirect_back fallback_location: orders_path, notice: "#{orders.count}건 처리 완료"
  end

  def export_csv
    orders = Order.where(id: params[:order_ids])
    send_data OrderCsvExporter.new(orders).call,
              filename: "orders_#{Date.today}.csv",
              type: "text/csv"
  end
end
```

### Stimulus (bulk_select_controller.js)
```js
// 체크박스 전체 선택 / 개별 선택 / 선택 카운트 표시
// 선택 시 하단 고정 액션 바 표시
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "actionBar", "count"]

  toggleAll() { /* 전체 선택/해제 */ }
  updateCount() { /* 선택 수 업데이트, 액션바 show/hide */ }
}
```

### 뷰 (orders/index — 하단 고정 액션 바)
```erb
<div data-controller="bulk-select">
  <!-- 테이블 각 행에 체크박스 추가 -->
  <!-- 하단 고정 바: "N개 선택됨 | 상태변경 | 담당자배정 | CSV 내보내기" -->
</div>
```

### 라우트
```ruby
namespace :orders do
  resource :bulk, only: [] do
    post :update
    post :export_csv
  end
end
```

---

## Feature 4: 견적 비교표 (Multi-Supplier Quotes)

### DB 변경
```ruby
# migration: create_order_quotes
create_table :order_quotes do |t|
  t.references :order,    null: false, foreign_key: true
  t.references :supplier, null: false, foreign_key: true
  t.decimal  :unit_price,   precision: 12, scale: 2
  t.string   :currency,     default: "USD"
  t.integer  :lead_time_days
  t.date     :validity_date
  t.text     :notes
  t.boolean  :selected,     default: false
  t.datetime :submitted_at
  t.timestamps
end
```

### 신규 파일
```
app/models/order_quote.rb
app/controllers/order_quotes_controller.rb
app/views/order_quotes/_form.html.erb
app/views/order_quotes/_comparison.html.erb  # 비교 테이블
```

### 비교 뷰
```erb
<%# app/views/order_quotes/_comparison.html.erb %>
<table>
  <thead>
    <tr>
      <th>거래처</th><th>단가</th><th>납기</th><th>유효기간</th><th>메모</th><th>선택</th>
    </tr>
  </thead>
  <tbody>
    <% order.order_quotes.order(:unit_price).each do |q| %>
      <tr class="<%= q.selected? ? 'bg-green-50' : '' %>">
        <td><%= q.supplier.name %></td>
        <td><%= number_to_currency(q.unit_price) %></td>
        <td><%= q.lead_time_days %>일</td>
        <td><%= q.validity_date %></td>
        <td><%= q.notes %></td>
        <td>
          <%= button_to "선택 확정", select_order_quote_path(q), method: :patch %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

### 라우트
```ruby
resources :orders do
  resources :order_quotes, shallow: true do
    member { patch :select }
  end
end
```

---

## Feature 5: Command Palette (Cmd+K 통합검색)

### DB 변경
없음

### 신규 파일
```
app/controllers/search_controller.rb
app/javascript/controllers/command_palette_controller.js
app/views/search/results.turbo_stream.erb
```

### 검색 API
```ruby
# app/controllers/search_controller.rb
class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    return render json: [] if q.length < 2

    results = []
    results += Order.where("title LIKE ?", "%#{q}%").limit(5)
                    .map { |o| { type: "order", label: o.title, url: order_path(o) } }
    results += Client.where("name LIKE ?", "%#{q}%").limit(3)
                     .map { |c| { type: "client", label: c.name, url: client_path(c) } }
    results += Supplier.where("name LIKE ?", "%#{q}%").limit(3)
                        .map { |s| { type: "supplier", label: s.name, url: supplier_path(s) } }
    results += Employee.where("name LIKE ? OR name_en LIKE ?", "%#{q}%", "%#{q}%").limit(3)
                        .map { |e| { type: "employee", label: e.name, url: employee_path(e) } }

    render json: results
  end
end
```

### Stimulus (command_palette_controller.js)
```js
// Cmd+K (Mac) / Ctrl+K (Win) 트리거
// 모달 팝업 → 검색어 입력 → 디바운스 300ms → API 호출 → 결과 표시
// 키보드 ↑↓ 결과 탐색, Enter 이동, Esc 닫기
```

### 레이아웃 통합
```erb
<%# application.html.erb body 끝에 %>
<div data-controller="command-palette" id="command-palette">
  <!-- 모달 오버레이 + 검색창 + 결과 목록 -->
</div>
```

### 라우트
```ruby
get '/search', to: 'search#index'
```

---

## Feature 6: 납기 위험도 자동 계산

### DB 변경
```ruby
# migration: add_risk_to_orders
add_column :orders, :risk_score, :integer, default: 0   # 0-100
add_column :orders, :risk_level, :string,  default: "low"  # low/medium/high/critical
add_column :orders, :risk_updated_at, :datetime
```

### 위험도 계산 로직
```ruby
# app/services/risk_assessment_service.rb
class RiskAssessmentService
  STAGE_DAYS = {          # 각 스테이지 평균 소요일
    "inbox"      => 1,
    "reviewing"  => 3,
    "quoted"     => 5,
    "confirmed"  => 2,
    "procuring"  => 14,
    "qa"         => 3,
    "delivered"  => 0
  }

  def self.calculate(order)
    return 0 if order.delivered? || order.due_date.nil?

    days_left        = (order.due_date - Date.today).to_i
    remaining_stages = stages_remaining(order.status)
    min_days_needed  = remaining_stages.sum { |s| STAGE_DAYS[s] }

    if days_left < 0               then score = 100  # 이미 지연
    elsif days_left < min_days_needed then score = 90 # 물리적 불가
    elsif days_left <= 7           then score = 75
    elsif days_left <= 14          then score = 50
    elsif days_left <= 30          then score = 25
    else                                score = 10
    end

    level = case score
            when 90..100 then "critical"
            when 75..89  then "high"
            when 50..74  then "medium"
            else              "low"
            end

    { score: score, level: level }
  end
end
```

### 배치 Job
```ruby
# app/jobs/risk_assessment_job.rb
class RiskAssessmentJob < ApplicationJob
  def perform
    Order.where.not(status: :delivered).find_each do |order|
      result = RiskAssessmentService.calculate(order)
      order.update_columns(
        risk_score: result[:score],
        risk_level: result[:level],
        risk_updated_at: Time.current
      )
    end
  end
end
```

### 위험도 배지 헬퍼
```ruby
# app/helpers/risk_helper.rb
module RiskHelper
  def risk_badge(order)
    return "" if order.risk_level.blank?
    css = { "critical" => "bg-red-100 text-red-700",
            "high"     => "bg-orange-100 text-orange-700",
            "medium"   => "bg-yellow-100 text-yellow-700",
            "low"      => "bg-green-100 text-green-700" }
    icon = { "critical" => "🔴", "high" => "🟠", "medium" => "🟡", "low" => "🟢" }
    "<span class='#{css[order.risk_level]} px-2 py-0.5 rounded-full text-xs'>
      #{icon[order.risk_level]} #{order.risk_level.upcase}
    </span>".html_safe
  end
end
```

---

## Feature 7: 경영 리포트 대시보드

### DB 변경
없음 (기존 데이터 집계)

### 신규 파일
```
app/controllers/reports_controller.rb
app/views/reports/index.html.erb
```

### 컨트롤러
```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  before_action :require_admin!

  def index
    @period = params[:period] || "month"
    @year   = params[:year]&.to_i  || Date.today.year
    @month  = params[:month]&.to_i || Date.today.month

    # 월별 수주/납품 트렌드 (12개월)
    @monthly_trend = Order.group_by_month(:created_at, last: 12)
                          .count

    # 거래처별 발주 비중
    @by_client = Order.joins(:client)
                      .group("clients.name")
                      .sum(:estimated_value)
                      .sort_by { |_, v| -v.to_f }
                      .first(10)

    # 거래처별 발주 비중
    @by_supplier = Order.joins(:supplier)
                        .group("suppliers.name")
                        .count
                        .sort_by { |_, v| -v }
                        .first(10)

    # 직원별 처리 건수 / 납기 준수율
    @by_assignee = User.joins(:assigned_orders)
                       .group("users.name")
                       .select("users.name,
                                COUNT(*) as total_orders,
                                SUM(CASE WHEN orders.status = 'delivered' THEN 1 ELSE 0 END) as delivered_count")
                       .map { |u| { name: u.name, total: u.total_orders, delivered: u.delivered_count } }

    # 현장 카테고리별 수주액
    @by_project_type = Project.joins(:orders)
                               .group("projects.project_type")
                               .sum("orders.estimated_value")

    # 이번달 KPI
    month_start = Date.today.beginning_of_month
    @kpi = {
      new_orders:    Order.where(created_at: month_start..).count,
      delivered:     Order.delivered.where(updated_at: month_start..).count,
      total_value:   Order.where(created_at: month_start..).sum(:estimated_value),
      on_time_rate:  calculate_on_time_rate(month_start)
    }
  end

  private

  def calculate_on_time_rate(from)
    delivered = Order.delivered.where(updated_at: from..)
    return 0 if delivered.empty?
    on_time = delivered.where("due_date >= DATE(updated_at)").count
    (on_time.to_f / delivered.count * 100).round(1)
  end
end
```

### 라우트
```ruby
resource :reports, only: [:index]
# 또는
get '/reports', to: 'reports#index'
```

---

## 구현 순서 (Do Phase)

### Step 1: DB 마이그레이션 (5분)
```bash
bin/rails g migration AddRiskToOrders risk_score:integer risk_level:string risk_updated_at:datetime
bin/rails g migration CreateNotifications user:references notifiable:references{polymorphic} title:string body:text notification_type:string read_at:datetime
bin/rails g migration CreateOrderQuotes order:references supplier:references unit_price:decimal currency:string lead_time_days:integer validity_date:date notes:text selected:boolean submitted_at:datetime
bin/rails db:migrate
```

### Step 2: Gem 추가 (5분)
```ruby
# Gemfile
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'
gem 'groupdate'   # 월별 집계용
gem 'http'        # Google Chat HTTP 요청
```

### Step 3: Phase A 병렬 구현
- Feature 5: Command Palette (JS + Search API)
- Feature 6: 위험도 계산 (Service + Job + 배지)
- Feature 7: 경영 리포트 (Controller + View)

### Step 4: Phase B
- Feature 2: 알림 + Google Chat
- Feature 3: Bulk Actions
- Feature 1: PDF 생성

### Step 5: Phase C
- Feature 4: 견적 비교표

---

## 파일 변경 요약

| 파일 | 변경 유형 |
|------|-----------|
| `Gemfile` | wicked_pdf, wkhtmltopdf-binary, groupdate, http 추가 |
| `config/routes.rb` | 7개 기능 라우트 추가 |
| `app/models/notification.rb` | 신규 |
| `app/models/order_quote.rb` | 신규 |
| `app/models/order.rb` | risk_score, risk_level 관계 추가 |
| `app/controllers/orders/pdf_controller.rb` | 신규 |
| `app/controllers/orders/bulk_controller.rb` | 신규 |
| `app/controllers/notifications_controller.rb` | 신규 |
| `app/controllers/order_quotes_controller.rb` | 신규 |
| `app/controllers/search_controller.rb` | 신규 |
| `app/controllers/reports_controller.rb` | 신규 |
| `app/services/risk_assessment_service.rb` | 신규 |
| `app/services/google_chat_service.rb` | 신규 |
| `app/jobs/risk_assessment_job.rb` | 신규 |
| `app/jobs/notification_delivery_job.rb` | 신규 |
| `app/javascript/controllers/command_palette_controller.js` | 신규 |
| `app/javascript/controllers/bulk_select_controller.js` | 신규 |
| `app/views/orders/show.html.erb` | PDF 버튼, 견적비교, 위험도 배지 추가 |
| `app/views/orders/index.html.erb` | 체크박스, 위험도 배지, 액션바 추가 |
| `app/views/layouts/application.html.erb` | Command Palette, 알림 배지 추가 |
| `app/views/reports/index.html.erb` | 신규 |
| `app/views/notifications/index.html.erb` | 신규 |
