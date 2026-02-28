# dashboard-ux Design

## 1. Overview

**Feature**: dashboard-ux
**Phase**: Design
**Created**: 2026-02-28
**References**: `docs/01-plan/features/dashboard-ux.plan.md`

대시보드 UX 3가지 개선 — Quick Actions, KPI 카드 드릴다운, 트렌드 SVG 아이콘 + 스파크라인.

---

## 2. Architecture

### 2.1 Data Flow

```
DashboardController#index
  ↓ 기존 KPI 데이터 유지
  ↓ 추가:
    @overdue_orders_brief  (limit 8, includes :client, :assignees)
    @urgent_orders_brief   (limit 8, includes :client, :assignees)
    @daily_sparkline       (최근 7일 일별 수주 건수 배열)
  ↓ ERB 렌더링:
    - page_title 옆 Quick Actions 3개 버튼 (FR-01)
    - KPI 카드 지연/긴급: cursor-pointer + onclick=toggleKpiPanel()
    - 드릴다운 패널 (col-span-full, hidden 토글) (FR-02)
    - ▲▼ → SVG 화살표 아이콘 교체 (FR-03)
    - 진행 중 카드 하단 미니 스파크라인 (FR-03)
```

### 2.2 Files to Modify

| File | 변경 내용 |
|------|-----------|
| `app/controllers/dashboard_controller.rb` | @overdue_orders_brief, @urgent_orders_brief, @daily_sparkline 추가 |
| `app/views/dashboard/index.html.erb` | Quick Actions + 드릴다운 패널 + SVG 아이콘 + 스파크라인 |

---

## 3. Detailed Design

### 3.1 Controller 추가 (FR-02, FR-03)

기존 `index` 액션 말미에 추가:

```ruby
# FR-02: KPI 드릴다운 데이터
@overdue_orders_brief = Order.overdue.by_due_date.limit(8).includes(:client, :assignees)
@urgent_orders_brief  = Order.urgent.by_due_date.limit(8).includes(:client, :assignees)

# FR-03: 7일 스파크라인
@daily_sparkline = (6.downto(0)).map do |i|
  day = Date.today - i.days
  Order.where(created_at: day.beginning_of_day..day.end_of_day).count
end
```

### 3.2 View: Quick Actions 버튼 (FR-01)

ROW1 KPI 그리드 바로 앞, 헤더 블록(page_title) 추가:

```erb
<%# dashboard-ux FR-01: Quick Actions %>
<div class="flex items-center justify-between mb-6">
  <div>
    <h1 class="text-2xl font-bold text-gray-900 dark:text-white">대시보드</h1>
    <p class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">전체 발주 현황 및 KPI</p>
  </div>
  <div class="flex items-center gap-2">
    <%# 신규 발주 (accent) %>
    <%= link_to new_order_path,
          class: "flex items-center gap-1.5 px-3 py-2 bg-accent text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors" do %>
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
      </svg>
      신규 발주
    <% end %>
    <%# 캘린더 (secondary) %>
    <%= link_to calendar_path,
          class: "flex items-center gap-1.5 px-3 py-2 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 text-sm font-medium rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors" do %>
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/>
        <line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
      </svg>
      캘린더
    <% end %>
    <%# 칸반 (secondary) %>
    <%= link_to kanban_path,
          class: "flex items-center gap-1.5 px-3 py-2 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 text-sm font-medium rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors" do %>
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="3" width="7" height="18" rx="1"/><rect x="14" y="3" width="7" height="10" rx="1"/>
        <rect x="14" y="17" width="7" height="4" rx="1"/>
      </svg>
      칸반
    <% end %>
  </div>
</div>
```

### 3.3 View: KPI 카드 드릴다운 (FR-02)

**KPI 그리드 구조 변경**: 기존 `grid` div에 드릴다운 패널을 col-span-full로 삽입.

지연 카드 변경:
```erb
<%# 기존: div.bg-white %>
<%# 변경: cursor-pointer + onclick %>
<div class="bg-white dark:bg-gray-800 rounded-xl border
            <%= @overdue_count > 0 ? 'border-red-200 dark:border-red-700 bg-red-50 dark:bg-red-900/20' : 'border-gray-200 dark:border-gray-700' %>
            p-4 cursor-pointer select-none"
     onclick="toggleKpiPanel('overdue')">
  ... (기존 내용 유지) ...
  <%# 클릭 힌트 %>
  <% if @overdue_count > 0 %>
    <p class="text-xs text-red-400 dark:text-red-500 mt-1.5">클릭하여 목록 보기</p>
  <% end %>
</div>
```

긴급 카드 변경 (동일 패턴, `'urgent'`):
```erb
<div class="... cursor-pointer select-none" onclick="toggleKpiPanel('urgent')">
  ...
  <% if @urgent_count > 0 %>
    <p class="text-xs text-orange-400 dark:text-orange-500 mt-1.5">클릭하여 목록 보기</p>
  <% end %>
</div>
```

드릴다운 패널 (KPI 그리드 내부, 지연/긴급 카드 각각):
```erb
<%# 드릴다운 패널: 지연 주문 %>
<div id="kpi-panel-overdue"
     class="hidden col-span-2 lg:col-span-3 xl:col-span-6
            bg-red-50 dark:bg-red-900/10 border border-red-200 dark:border-red-800
            rounded-xl overflow-hidden">
  <div class="px-4 py-3 border-b border-red-100 dark:border-red-800 flex items-center justify-between">
    <p class="text-sm font-semibold text-red-700 dark:text-red-400">지연 주문 (최대 8건)</p>
    <button onclick="toggleKpiPanel('overdue')" class="text-red-400 hover:text-red-600">
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    </button>
  </div>
  <div class="divide-y divide-red-100 dark:divide-red-800/50">
    <% @overdue_orders_brief.each do |order| %>
      <div class="flex items-center gap-3 px-4 py-2.5 hover:bg-red-100/50 dark:hover:bg-red-900/20 cursor-pointer transition-colors"
           onclick="openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= order.title %></p>
          <p class="text-xs text-gray-500 dark:text-gray-400 truncate">
            <%= order.client&.name || order.customer_name %>
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <%= status_badge(order) %>
          <%= due_badge(order) %>
        </div>
      </div>
    <% end %>
  </div>
</div>

<%# 드릴다운 패널: 긴급 주문 (D-7) %>
<div id="kpi-panel-urgent"
     class="hidden col-span-2 lg:col-span-3 xl:col-span-6
            bg-orange-50 dark:bg-orange-900/10 border border-orange-200 dark:border-orange-800
            rounded-xl overflow-hidden">
  <div class="px-4 py-3 border-b border-orange-100 dark:border-orange-800 flex items-center justify-between">
    <p class="text-sm font-semibold text-orange-700 dark:text-orange-400">긴급 D-7 주문 (최대 8건)</p>
    <button onclick="toggleKpiPanel('urgent')" class="text-orange-400 hover:text-orange-600">
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    </button>
  </div>
  <div class="divide-y divide-orange-100 dark:divide-orange-800/50">
    <% @urgent_orders_brief.each do |order| %>
      <div class="flex items-center gap-3 px-4 py-2.5 hover:bg-orange-100/50 dark:hover:bg-orange-900/20 cursor-pointer transition-colors"
           onclick="openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= order.title %></p>
          <p class="text-xs text-gray-500 dark:text-gray-400 truncate">
            <%= order.client&.name || order.customer_name %>
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <%= status_badge(order) %>
          <%= due_badge(order) %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

JS 토글 함수:
```javascript
function toggleKpiPanel(type) {
  var panels = ['overdue', 'urgent'];
  var panel  = document.getElementById('kpi-panel-' + type);
  var isHidden = panel.classList.contains('hidden');
  // 모든 패널 닫기
  panels.forEach(function(t) {
    document.getElementById('kpi-panel-' + t).classList.add('hidden');
  });
  // 닫혀 있었으면 열기
  if (isHidden) panel.classList.remove('hidden');
}
```

### 3.4 View: 트렌드 SVG 아이콘 교체 (FR-03)

**납기 준수율 카드** (line 85~86):
```erb
<%# 변경 전 %>
<%= rate_trend >= 0 ? '▲' : '▼' %> <%= rate_trend.abs.round(1) %>% 전월 대비

<%# 변경 후 %>
<span class="inline-flex items-center gap-0.5">
  <% if rate_trend >= 0 %>
    <svg class="w-3 h-3 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="18 15 12 9 6 15"/>
    </svg>
  <% else %>
    <svg class="w-3 h-3 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="6 9 12 15 18 9"/>
    </svg>
  <% end %>
  <%= rate_trend.abs.round(1) %>% 전월 대비
</span>
```

**수주액 카드** (line 104~106):
```erb
<%# 변경 전 %>
<%= value_trend >= 0 ? '▲' : '▼' %> <%= value_trend.abs %>% 전월 대비

<%# 변경 후 %>
<span class="inline-flex items-center gap-0.5">
  <% if value_trend >= 0 %>
    <svg class="w-3 h-3 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="18 15 12 9 6 15"/>
    </svg>
  <% else %>
    <svg class="w-3 h-3 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="6 9 12 15 18 9"/>
    </svg>
  <% end %>
  <%= value_trend.abs %>% 전월 대비
</span>
```

### 3.5 View: 미니 스파크라인 (FR-03)

**진행 중 카드** (카드 하단, `건` 텍스트 아래):
```erb
<%# FR-03: 7일 미니 스파크라인 %>
<% if @daily_sparkline.any?(&:positive?) %>
  <% max_s = [@daily_sparkline.max, 1].max %>
  <div class="flex items-end gap-px mt-3 h-6">
    <% @daily_sparkline.each do |val| %>
      <div class="flex-1 rounded-sm transition-all
                  bg-blue-200 dark:bg-blue-700/60"
           style="height: <%= [val.to_f / max_s * 100, 8].max.round %>%"
           title="<%= val %>건"></div>
    <% end %>
  </div>
  <p class="text-xs text-gray-400 dark:text-gray-500 mt-1">최근 7일 추이</p>
<% end %>
```

---

## 4. UI Mockup

### 4.1 헤더 + Quick Actions (FR-01)

```
┌──────────────────────────────────────────────────────┐
│ 대시보드                    [+ 신규 발주] [캘린더] [칸반] │
│ 전체 발주 현황 및 KPI                                  │
└──────────────────────────────────────────────────────┘
```

### 4.2 KPI 카드 드릴다운 (FR-02)

```
┌──────┐ ┌──────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ ┌──────┐
│ 12   │ │ 3    │ │ 5 지연↑  │ │ 2 긴급↑  │ │ 95%  │ │ $2M  │
│ 진행 │ │ 납품 │ │즉시조치  │ │7일내납기 │ │준수율│ │수주액│
│      │ │      │ │클릭 보기 │ │클릭 보기 │ │      │ │      │
└──────┘ └──────┘ └──────────┘ └──────────┘ └──────┘ └──────┘

[클릭 후 드릴다운 패널 확장]
┌─────────────────────────────────────────────────────────────┐
│ 지연 주문 (최대 8건)                                    [✕] │
├─────────────────────────────────────────────────────────────┤
│ Valve Assembly    ABC Corp           confirmed  D+3         │
│ Pump Unit         XYZ Ltd            procuring  D+1         │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 트렌드 아이콘 + 스파크라인 (FR-03)

```
┌──────────────────────────┐
│ 12                       │
│ 진행 중                  │
│ 건                       │
│ ▁▃▅▂▇▄█  ← 미니 스파크라인│
│ 최근 7일 추이             │
└──────────────────────────┘

납기 준수율 카드:
│ ↑ 2.3% 전월 대비  (SVG 화살표) │
```

---

## 5. Implementation Order

1. `dashboard_controller.rb` — @overdue_orders_brief, @urgent_orders_brief, @daily_sparkline 추가
2. `index.html.erb` — 헤더 Quick Actions 블록 추가 (ROW1 상단)
3. `index.html.erb` — 지연/긴급 KPI 카드 cursor-pointer + onclick + "클릭하여 목록 보기" 텍스트
4. `index.html.erb` — 드릴다운 패널 (overdue/urgent) col-span-full 추가
5. `index.html.erb` — toggleKpiPanel JS 함수 추가 (script 섹션)
6. `index.html.erb` — 납기준수율/수주액 카드 ▲▼ → SVG 화살표 교체
7. `index.html.erb` — 진행 중 카드 미니 스파크라인 추가

---

## 6. Completion Criteria

| # | Criteria | 검증 방법 |
|---|----------|-----------|
| 1 | 헤더 Quick Actions 3버튼 (신규발주/캘린더/칸반) 표시 | HTML 확인 |
| 2 | 지연/긴급 KPI 카드 cursor-pointer + onclick=toggleKpiPanel | HTML 확인 |
| 3 | 드릴다운 패널 hidden 토글 + openOrderDrawer 연동 | JS 함수 확인 |
| 4 | 납기준수율/수주액 카드 SVG 화살표 아이콘 (▲▼ 텍스트 제거) | HTML 확인 |
| 5 | 진행 중 카드 @daily_sparkline 기반 미니 스파크라인 | HTML 확인 |
| 6 | Gap Analysis Match Rate >= 90% | gap-detector |

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
