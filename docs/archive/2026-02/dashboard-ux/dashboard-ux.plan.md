# dashboard-ux Plan

## 1. Feature Overview

**Feature Name**: dashboard-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (2 files)

### 1.1 Summary

대시보드 UX 3가지 개선 —
(1) 헤더 Quick Actions 버튼 (신규발주/캘린더/칸반),
(2) KPI 카드 클릭 시 필터된 주문 목록 슬라이드다운 패널,
(3) 수주액/납기준수율 트렌드 ▲▼ 텍스트를 SVG 아이콘으로 교체 + 미니 스파크라인 추가.

### 1.2 Current State (실측)

**`app/controllers/dashboard_controller.rb`** (168줄):
- KPI: @total_active, @overdue_count, @urgent_count, @delivered_this_month
- @on_time_rate_this_month / last_month, @total_value_this_month / last_month
- @urgent_orders (limit 5), @recent_orders (limit 8)
- @weekly_data, @monthly_data, @quarterly_data, @yearly_data

**`app/views/dashboard/index.html.erb`** (631줄):
- ROW1: KPI 6카드 — 클릭 이벤트 없음, ▲▼ 텍스트 트렌드
- ROW2: 파이프라인 + 현장 카테고리
- ROW3: 기간별 트렌드 차트
- ROW4: 긴급납기 + 비자/계약만료 + Sheets + 최근발주
- ROW5: Top5 발주처/거래처
- ROW6: 담당자별 워크로드
- Quick Actions 버튼 없음 (신규발주 버튼은 최하단에만)

**문제점**:
1. **Quick Actions 없음**: 신규 발주, 캘린더, 칸반 이동 버튼이 상단에 없어 여러 단계 클릭 필요
2. **KPI 카드 클릭 무반응**: 지연/긴급 카드 클릭 시 해당 주문 목록을 즉시 볼 수 없음
3. **트렌드 텍스트 아이콘**: ▲▼ 유니코드 대신 SVG 아이콘 + 미니 스파크라인 없음

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **Quick Actions**: 헤더 우측에 신규발주/캘린더/칸반 3개 버튼 |
| FR-02 | **KPI 카드 드릴다운**: 지연(overdue)/긴급(urgent) 카드 클릭 시 슬라이드다운 주문 목록 패널 |
| FR-03 | **트렌드 시각화**: ▲▼ 텍스트 → SVG 화살표 아이콘 + KPI 카드에 7일 미니 스파크라인 |

### Out of Scope
- 드래그 가능한 대시보드 위젯
- 실시간 WebSocket 갱신
- 대시보드 레이아웃 커스터마이징

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/controllers/dashboard_controller.rb` | @daily_sparkline 데이터 추가 (7일) |
| `app/views/dashboard/index.html.erb` | Quick Actions + KPI 드릴다운 + 트렌드 아이콘 |

### 3.2 Controller: 7일 스파크라인 데이터 (FR-03)

```ruby
# 최근 7일 일별 생성 건수 (스파크라인용)
@daily_sparkline = (6.downto(0)).map do |i|
  day = Date.today - i.days
  Order.where(created_at: day.beginning_of_day..day.end_of_day).count
end
```

### 3.3 View: Quick Actions 버튼 (FR-01)

헤더 영역 (page_title 아래) 또는 ROW1 상단에 배치:

```
┌──────────────────────────────────────────┐
│ 대시보드                 [+ 신규발주]     │
│                    [캘린더] [칸반보기]    │
└──────────────────────────────────────────┘
```

```erb
<div class="flex items-center gap-2">
  <%= link_to new_order_path, class: "btn-primary" do %>
    <svg>...</svg> 신규 발주
  <% end %>
  <%= link_to calendar_path, class: "btn-secondary" do %>
    <svg>...</svg> 캘린더
  <% end %>
  <%= link_to kanban_path, class: "btn-secondary" do %>
    <svg>...</svg> 칸반
  <% end %>
</div>
```

### 3.4 View: KPI 카드 드릴다운 (FR-02)

지연/긴급 카드에 `onclick` + 토글 패널:

```javascript
function toggleKpiPanel(type) {
  var panel = document.getElementById('kpi-panel-' + type);
  var isHidden = panel.classList.contains('hidden');
  // 다른 패널 닫기
  ['overdue', 'urgent'].forEach(function(t) {
    document.getElementById('kpi-panel-' + t).classList.add('hidden');
  });
  if (isHidden) panel.classList.remove('hidden');
}
```

ERB: KPI 카드에 cursor-pointer + onclick 추가, 카드 바로 아래 패널 div:

```erb
<!-- KPI 카드 (지연) -->
<div class="... cursor-pointer" onclick="toggleKpiPanel('overdue')">
  ...
</div>
<!-- 드릴다운 패널 -->
<div id="kpi-panel-overdue" class="hidden col-span-full bg-red-50 ...">
  <% @overdue_orders_brief.each do |o| %>
    주문 행 (title, status, due_badge, openOrderDrawer)
  <% end %>
</div>
```

컨트롤러에 `@overdue_orders_brief`, `@urgent_orders_brief` 추가:

```ruby
@overdue_orders_brief = Order.overdue.by_due_date.limit(8).includes(:client, :assignees)
@urgent_orders_brief  = Order.urgent.by_due_date.limit(8).includes(:client, :assignees)
```

### 3.5 View: 트렌드 SVG 아이콘 + 스파크라인 (FR-03)

▲▼ 텍스트 교체:

```erb
<%# 변경 전 %>
<%= rate_trend >= 0 ? '▲' : '▼' %> <%= rate_trend.abs %>%

<%# 변경 후 %>
<% if rate_trend >= 0 %>
  <svg class="w-3 h-3 inline text-green-500" ...>arrow-up</svg>
<% else %>
  <svg class="w-3 h-3 inline text-red-500" ...>arrow-down</svg>
<% end %>
<%= rate_trend.abs %>%
```

미니 스파크라인 (진행 중 카드에 추가):

```erb
<%# @daily_sparkline: [3,5,2,8,4,6,9] 형태 %>
<% max_s = [@daily_sparkline.max, 1].max %>
<div class="flex items-end gap-px h-6 mt-2">
  <% @daily_sparkline.each do |val| %>
    <div class="flex-1 bg-blue-200 dark:bg-blue-800 rounded-sm"
         style="height: <%= (val.to_f / max_s * 100).round %>%"></div>
  <% end %>
</div>
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 헤더에 Quick Actions 3개 버튼 표시 (신규발주/캘린더/칸반) |
| 2 | 지연/긴급 KPI 카드 클릭 시 드릴다운 패널 토글 |
| 3 | 드릴다운 패널에 주문 목록 표시 (title, due_badge, openOrderDrawer 연동) |
| 4 | ▲▼ 텍스트 → SVG 화살표 아이콘으로 교체 (납기준수율 + 수주액 카드) |
| 5 | 진행 중 카드에 7일 미니 스파크라인 표시 |
| 6 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `Order.overdue`, `Order.urgent` scope — 기존 존재
- `openOrderDrawer()` JS 함수 — layout에 기존 존재
- `due_badge(order)` 헬퍼 — 기존 존재
- `new_order_path`, `calendar_path`, `kanban_path` — 기존 존재

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
