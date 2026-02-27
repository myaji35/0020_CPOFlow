# Design: 경영 리포트 고도화 (management-report)

## 개요
- **Feature**: management-report
- **작성일**: 2026-02-28
- **참조 Plan**: `docs/01-plan/features/management-report.plan.md`

---

## 전체 흐름

```
사용자 (/reports?period=this_month&from=&to=)
  │
  ▼
ReportsController#index
  ├── parse_period_params   → start_date, end_date 계산
  ├── kpi_data             → 이번달 KPI + 전월 비교
  ├── monthly_trend        → 12개월 수주/납품 트렌드
  ├── pipeline_funnel      → 7단계 상태별 건수
  ├── by_client            → 발주처별 수주액 Top 10
  ├── by_supplier          → 거래처별 발주 건수 Top 10
  ├── by_project           → 프로젝트별 수주액 Top 10
  └── by_assignee          → 담당자별 성과

ReportsController#export_csv  → CSV 스트리밍 다운로드

views/reports/index.html.erb
  ├── [Turbo Frame: filters]   기간 필터 폼
  ├── [Turbo Frame: kpi]       KPI 카드 6개 + 증감률
  ├── [Turbo Frame: charts]    Chart.js 트렌드 차트
  ├── [Turbo Frame: funnel]    파이프라인 퍼널
  ├── [Turbo Frame: tops]      발주처/거래처/프로젝트 Top 10
  ├── [Turbo Frame: assignee]  담당자별 성과 테이블
  └── [Print CSS]              인쇄 최적화
```

---

## 1. 컨트롤러 설계

### `app/controllers/reports_controller.rb`

```ruby
class ReportsController < ApplicationController
  before_action :require_admin_or_manager!

  def index
    @period   = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])

    @kpi          = build_kpi(@date_range)
    @monthly      = build_monthly_trend          # 항상 최근 12개월 고정
    @funnel       = build_funnel                 # 전체 진행중 주문
    @by_client    = build_by_client(@date_range)
    @by_supplier  = build_by_supplier(@date_range)
    @by_project   = build_by_project(@date_range)
    @by_assignee  = build_by_assignee(@date_range)
  end

  def export_csv
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    orders      = Order.includes(:client, :supplier, :project, :user)
                       .where(created_at: @date_range)
                       .order(created_at: :desc)

    respond_to do |format|
      format.csv do
        send_data generate_csv(orders),
                  filename: "orders_#{Date.today}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  end

  private

  # 기간 파라미터 파싱 → Range 반환
  def parse_period(period, from, to)
    case period
    when "this_month"   then Date.today.beginning_of_month..Date.today.end_of_month
    when "last_month"   then 1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when "this_quarter" then Date.today.beginning_of_quarter..Date.today.end_of_quarter
    when "this_year"    then Date.today.beginning_of_year..Date.today.end_of_year
    when "custom"
      f = Date.parse(from) rescue Date.today.beginning_of_month
      t = Date.parse(to)   rescue Date.today
      f..t
    else
      Date.today.beginning_of_month..Date.today.end_of_month
    end
  end

  # KPI: 현재 기간 + 전기 대비 증감
  def build_kpi(range)
    prev_range = calc_prev_range(range)
    curr = order_stats(range)
    prev = order_stats(prev_range)

    {
      new_orders:    curr[:count],
      prev_orders:   prev[:count],
      delivered:     curr[:delivered],
      prev_delivered: prev[:delivered],
      total_value:   curr[:value],
      prev_value:    prev[:value],
      on_time_rate:  curr[:on_time_rate],
      prev_on_time:  prev[:on_time_rate],
      overdue:       Order.where("due_date < ?", Date.today).where.not(status: :delivered).count,
      urgent:        Order.where(priority: :urgent).where.not(status: :delivered).count,
      avg_lead_days: calc_avg_lead_days(range)
    }
  end

  def order_stats(range)
    base      = Order.where(created_at: range)
    delivered = Order.delivered.where(updated_at: range)
    on_time   = delivered.where("due_date >= DATE(updated_at)").count
    {
      count:        base.count,
      delivered:    delivered.count,
      value:        base.sum(:estimated_value).to_f,
      on_time_rate: delivered.any? ? (on_time.to_f / delivered.count * 100).round(1) : 0.0
    }
  end

  def calc_prev_range(range)
    duration = range.last - range.first
    (range.first - duration - 1)..(range.first - 1)
  end

  def calc_avg_lead_days(range)
    # inbox→delivered 평균 일수
    delivered = Order.delivered.where(updated_at: range)
    return 0 if delivered.empty?
    total = delivered.sum { |o| (o.updated_at.to_date - o.created_at.to_date).to_i }
    (total.to_f / delivered.count).round(1)
  end

  # 월별 트렌드 (최근 12개월 — 기간 필터 무관)
  def build_monthly_trend
    months = (11.downto(0)).map { |i| i.months.ago.beginning_of_month }
    months.map do |m|
      range = m..(m.end_of_month)
      {
        label:     m.strftime("%y.%m"),
        orders:    Order.where(created_at: range).count,
        delivered: Order.delivered.where(updated_at: range).count,
        value:     Order.where(created_at: range).sum(:estimated_value).to_f
      }
    end
  end

  # 파이프라인 퍼널 (현재 진행중)
  def build_funnel
    Order.group(:status).count
  end

  def build_by_client(range)
    Order.joins(:client).where(created_at: range)
         .group("clients.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  def build_by_supplier(range)
    Order.joins(:supplier).where(created_at: range)
         .group("suppliers.name").count
         .sort_by { |_, v| -v }.first(10)
  end

  def build_by_project(range)
    Order.joins(:project).where(created_at: range)
         .group("projects.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  def build_by_assignee(range)
    User.joins(:orders).where(orders: { created_at: range })
        .group("users.id", "users.name")
        .select(
          "users.id, users.name,
           COUNT(orders.id) AS order_count,
           SUM(CASE WHEN orders.status = 6 THEN 1 ELSE 0 END) AS delivered_count,
           SUM(CASE WHEN orders.status = 6 AND orders.due_date >= DATE(orders.updated_at) THEN 1 ELSE 0 END) AS on_time_count"
        )
  end

  def generate_csv(orders)
    require "csv"
    CSV.generate(encoding: "UTF-8") do |csv|
      csv << %w[주문ID 제목 발주처 거래처 프로젝트 수주액 상태 납기일 담당자 생성일]
      orders.each do |o|
        csv << [
          o.id, o.title,
          o.client&.name, o.supplier&.name, o.project&.name,
          o.estimated_value, o.status, o.due_date,
          o.user&.name, o.created_at.strftime("%Y-%m-%d")
        ]
      end
    end
  end

  def require_admin_or_manager!
    redirect_to root_path, alert: "접근 권한이 없습니다." unless current_user&.admin? || current_user&.manager?
  end
end
```

---

## 2. 라우트 설계

```ruby
# config/routes.rb 추가
get  "/reports",            to: "reports#index"
get  "/reports/export_csv", to: "reports#export_csv", as: :reports_export_csv
```

---

## 3. 뷰 설계

### `app/views/reports/index.html.erb` 구조

```
[헤더] 경영 리포트 | 기간 표시 | CSV 다운로드 | 인쇄 버튼
  │
  ├── [기간 필터 바]
  │     이번달 | 지난달 | 이번분기 | 올해 | 직접입력(from~to)
  │     → form GET /reports?period=xxx (Turbo)
  │
  ├── [KPI 카드 행] (7개)
  │     수주건수  납품건수  수주액  납기준수율  지연건수  긴급건수  평균소요일
  │     각 카드에 전기 대비 증감률 표시 (▲▼)
  │
  ├── [차트 행 2열]
  │     좌: [Chart.js] 월별 수주/납품 이중 선 그래프 + 수주액 막대
  │     우: [파이프라인 퍼널] 7단계 가로 막대
  │
  ├── [Top 10 행 3열]
  │     발주처별 수주액 | 거래처별 건수 | 프로젝트별 수주액
  │
  └── [담당자별 성과 테이블]
        이름 | 담당 건수 | 납품 건수 | 납기 준수율 | 진행중
```

### 기간 필터 UI

```html
<!-- 탭 형태 필터 -->
<div class="flex gap-1 bg-gray-100 dark:bg-gray-800 p-1 rounded-lg">
  <% [
    ["this_month",   "이번달"],
    ["last_month",   "지난달"],
    ["this_quarter", "이번분기"],
    ["this_year",    "올해"],
    ["custom",       "직접입력"]
  ].each do |val, label| %>
    <%= link_to label, reports_path(period: val),
          class: "px-3 py-1.5 rounded-md text-sm font-medium transition-colors
                  #{@period == val ? 'bg-white dark:bg-gray-700 shadow text-gray-900 dark:text-white'
                                   : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'}" %>
  <% end %>
</div>
<!-- 직접입력 시 date picker 표시 -->
```

### KPI 카드 증감률 컴포넌트

```erb
<%# 증감률 계산 헬퍼 %>
<% def delta_badge(curr, prev)
  return "" if prev == 0
  pct = ((curr - prev).to_f / prev * 100).round(1)
  arrow = pct >= 0 ? "▲" : "▼"
  color = pct >= 0 ? "text-green-600" : "text-red-500"
  "<span class='text-xs #{color} font-medium'>#{arrow} #{pct.abs}%</span>"
end %>
```

### Chart.js 설정

```javascript
// 월별 트렌드 — 이중 축 차트
const ctx = document.getElementById('trendChart');
new Chart(ctx, {
  type: 'bar',
  data: {
    labels: <%= @monthly.map { |m| m[:label] }.to_json.html_safe %>,
    datasets: [
      {
        type: 'line',
        label: '수주',
        data: <%= @monthly.map { |m| m[:orders] }.to_json.html_safe %>,
        borderColor: '#1E3A5F',
        tension: 0.3,
        yAxisID: 'y'
      },
      {
        type: 'line',
        label: '납품',
        data: <%= @monthly.map { |m| m[:delivered] }.to_json.html_safe %>,
        borderColor: '#1E8E3E',
        tension: 0.3,
        yAxisID: 'y'
      },
      {
        type: 'bar',
        label: '수주액($K)',
        data: <%= @monthly.map { |m| (m[:value] / 1000).round }.to_json.html_safe %>,
        backgroundColor: 'rgba(0,161,224,0.3)',
        yAxisID: 'y1'
      }
    ]
  },
  options: {
    responsive: true,
    scales: {
      y:  { position: 'left',  title: { display: true, text: '건수' } },
      y1: { position: 'right', title: { display: true, text: '$K' }, grid: { drawOnChartArea: false } }
    }
  }
});
```

### 파이프라인 퍼널

```erb
<% statuses = [
  ["inbox",     "Inbox",           "bg-gray-400"],
  ["reviewing", "Under Review",    "bg-blue-400"],
  ["quoted",    "Quoted",          "bg-indigo-400"],
  ["confirmed", "Confirmed",       "bg-purple-400"],
  ["procuring", "Procuring",       "bg-yellow-400"],
  ["qa",        "QA",              "bg-orange-400"],
  ["delivered", "Delivered",       "bg-green-500"]
] %>
<% total = [@funnel.values.sum, 1].max %>
<% statuses.each do |key, label, color| %>
  <% cnt = @funnel[key] || 0 %>
  <% pct = (cnt.to_f / total * 100).round(1) %>
  <div class="flex items-center gap-3 mb-2">
    <span class="text-xs text-gray-500 dark:text-gray-400 w-28"><%= label %></span>
    <div class="flex-1 bg-gray-100 dark:bg-gray-700 rounded-full h-5 relative">
      <div class="<%= color %> h-5 rounded-full" style="width:<%= [pct,1].max %>%"></div>
      <span class="absolute inset-0 flex items-center justify-center text-xs font-medium text-white mix-blend-difference">
        <%= cnt %>건
      </span>
    </div>
    <span class="text-xs text-gray-400 w-12 text-right"><%= pct %>%</span>
  </div>
<% end %>
```

### 담당자별 성과 테이블

```erb
<table class="w-full text-sm">
  <thead class="bg-gray-50 dark:bg-gray-700/50">
    <tr>
      <th class="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase">담당자</th>
      <th class="px-4 py-3 text-right text-xs font-semibold text-gray-500 uppercase">담당 건수</th>
      <th class="px-4 py-3 text-right text-xs font-semibold text-gray-500 uppercase">납품 건수</th>
      <th class="px-4 py-3 text-right text-xs font-semibold text-gray-500 uppercase">납기 준수율</th>
    </tr>
  </thead>
  <tbody>
    <% @by_assignee.each do |u| %>
      <% rate = u.delivered_count > 0 ? (u.on_time_count.to_f / u.delivered_count * 100).round(1) : 0 %>
      <tr class="border-t border-gray-100 dark:border-gray-700">
        <td class="px-4 py-3 font-medium text-gray-900 dark:text-white"><%= u.name %></td>
        <td class="px-4 py-3 text-right tabular-nums"><%= u.order_count %></td>
        <td class="px-4 py-3 text-right tabular-nums text-green-600"><%= u.delivered_count %></td>
        <td class="px-4 py-3 text-right tabular-nums">
          <span class="<%= rate >= 90 ? 'text-green-600' : rate >= 70 ? 'text-yellow-600' : 'text-red-500' %>">
            <%= rate %>%
          </span>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

---

## 4. Print CSS 설계

```html
<style>
  @media print {
    nav, aside, .no-print { display: none !important; }
    .print-break { page-break-before: always; }
    body { font-size: 11pt; }
    .bg-white { box-shadow: none !important; border: 1px solid #ddd !important; }
  }
</style>
```

---

## 5. CSV 라우트 추가

```ruby
# config/routes.rb
get "/reports/export_csv", to: "reports#export_csv", as: :reports_export_csv
```

---

## 6. 구현 순서

| Step | 작업 | 파일 |
|------|------|------|
| 1 | 라우트 추가 (export_csv) | `config/routes.rb` |
| 2 | 컨트롤러 전면 수정 | `app/controllers/reports_controller.rb` |
| 3 | 뷰 전면 재작성 (필터+KPI) | `app/views/reports/index.html.erb` |
| 4 | Chart.js CDN + 트렌드 차트 | 뷰 내 `<script>` |
| 5 | 파이프라인 퍼널 섹션 | 뷰 내 섹션 |
| 6 | Top 10 섹션 (3열) | 뷰 내 섹션 |
| 7 | 담당자별 성과 테이블 | 뷰 내 섹션 |
| 8 | Print CSS + 인쇄 버튼 | 뷰 내 `<style>` + 버튼 |

---

## 7. 보안 고려사항

- `before_action :require_admin_or_manager!` 유지
- CSV 파일명에 사용자 입력값 미사용 (날짜 자동 생성)
- `params[:from]`, `params[:to]` — `Date.parse rescue` 처리로 인젝션 방지
