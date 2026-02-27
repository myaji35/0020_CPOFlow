# calendar-ux Design

## 1. Overview

**Feature**: calendar-ux
**Phase**: Design
**Created**: 2026-02-28
**References**: `docs/01-plan/features/calendar-ux.plan.md`

납기일 캘린더 UX 개선 — 히트맵 강도, 위험도 배경색, 사이드 패널 카드 강화, 조회 범위 확장.

---

## 2. Architecture

### 2.1 Data Flow

```
CalendarController#index
  ↓ (grid_start..grid_end 범위 쿼리)
@orders (includes :assignees, :client, :project)
  ↓
orders_by_date Hash (group_by due_date)
  ↓
ERB 렌더링:
  - 날짜 셀: heatmap_bg + risk_bg + 주문 배지
  - data-orders JSON (client/project/assignee 포함)
  ↓
JavaScript:
  - 날짜 셀 클릭 → 사이드 패널 열기
  - 패널 카드 렌더링 (강화된 정보)
```

### 2.2 Files to Modify

| File | 변경 내용 |
|------|-----------|
| `app/controllers/calendar_controller.rb` | 조회 범위 확장 |
| `app/views/calendar/index.html.erb` | 히트맵 + 위험도 + 패널 강화 |

---

## 3. Detailed Design

### 3.1 Controller: 조회 범위 확장 (FR-04)

**변경 전**:
```ruby
@orders = Order.where(due_date: @month..@month.end_of_month)
```

**변경 후**:
```ruby
first_day  = @month.beginning_of_month
grid_start = first_day - first_day.wday.days
grid_end   = grid_start + 41.days  # 6주 (42일 - 1)

@orders = Order.where(due_date: grid_start..grid_end)
               .includes(:assignees, :client, :project)
               .by_due_date
```

`@stats`는 해당 월 주문만 카운트:
```ruby
month_orders = @orders.select { |o| o.due_date.month == @month.month && o.due_date.year == @month.year }
@stats = {
  total:   month_orders.count,
  overdue: month_orders.count { |o| o.due_date < today },
  urgent:  month_orders.count { |o| o.due_date >= today && o.due_date <= today + 7 },
  normal:  month_orders.count { |o| o.due_date > today + 7 }
}
```

### 3.2 View: 히트맵 강도 (FR-01)

날짜 셀의 `day_orders` 수에 따라 배경색 강도 4단계:

| 건수 | 클래스 (Light) | 클래스 (Dark) |
|------|---------------|--------------|
| 0 | (기본) | (기본) |
| 1 | `bg-blue-50` | `dark:bg-blue-900/10` |
| 2~3 | `bg-blue-100` | `dark:bg-blue-900/20` |
| 4~6 | `bg-blue-200` | `dark:bg-blue-900/30` |
| 7+ | `bg-blue-300` | `dark:bg-blue-900/40` |

ERB 헬퍼 (인라인):
```erb
<%
  heatmap_bg = case day_orders.size
               when 0    then ''
               when 1    then 'bg-blue-50 dark:bg-blue-900/10'
               when 2..3 then 'bg-blue-100 dark:bg-blue-900/20'
               when 4..6 then 'bg-blue-200 dark:bg-blue-900/30'
               else           'bg-blue-300 dark:bg-blue-900/40'
               end
%>
```

### 3.3 View: 위험도 배경색 (FR-02)

위험도가 히트맵보다 우선:

```erb
<%
  today = Date.today
  has_overdue = day_orders.any? { |o| o.due_date < today }
  has_urgent  = day_orders.any? { |o| o.due_date >= today && o.due_date <= today + 7 }

  risk_bg = if has_overdue
              'bg-red-50 dark:bg-red-900/15'
            elsif has_urgent
              'bg-orange-50 dark:bg-orange-900/15'
            else
              heatmap_bg
            end
%>
```

날짜 셀 클래스 적용:
```html
<div class="min-h-24 border-b border-r border-gray-50 dark:border-gray-700 p-2 cursor-pointer
            hover:opacity-90 transition-colors
            <%= is_current_month ? risk_bg || 'bg-white dark:bg-gray-800' : 'bg-gray-50 dark:bg-gray-700/30' %>
            <%= is_today ? 'ring-2 ring-inset ring-primary/30' : '' %>">
```

### 3.4 View: data-orders JSON 확장 (FR-03 준비)

```erb
<%
  day_orders_json = day_orders.map { |o|
    {
      id:       o.id,
      title:    o.title,
      path:     order_path(o),
      status:   Order::STATUS_LABELS[o.status],
      priority: o.priority,
      due_date: o.due_date.strftime("%m/%d"),
      client:   o.client&.name || o.customer_name,
      project:  o.project&.name,
      assignee: o.assignees.first&.name
    }
  }.to_json
%>
```

### 3.5 View: 사이드 패널 카드 강화 (FR-03)

**변경 전** (JavaScript):
```javascript
'<p class="text-sm font-medium">' + o.title + '</p>' +
'<p class="text-xs text-gray-500">' + o.status + '</p>' +
'<span class="badge">' + o.priority + '</span>'
```

**변경 후** (JavaScript):
```javascript
// 카드 레이아웃
┌─────────────────────────────────────────┐
│ [주문 제목]                   [D-badge]  │
│ client · project (있는 경우만)           │
│ [상태 배지]  [우선순위 배지]             │
│ 담당자: 이름 (있는 경우만)              │
└─────────────────────────────────────────┘
```

D-badge 계산 (JS):
```javascript
function dueBadge(dueDateStr) {
  // dueDateStr: "MM/DD" 형태
  // 오늘 기준 D-N 계산 (단순 표시용)
  return '<span class="text-xs text-gray-400">' + dueDateStr + '</span>';
}
```

우선순위 배지 (JS):
```javascript
var PRIORITY_LABELS = { urgent: 'URGENT', high: 'HIGH', medium: 'MEDIUM', low: 'LOW' };
var PRIORITY_COLORS = {
  urgent: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  high:   'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
  medium: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
  low:    'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
};
```

완성된 카드 HTML (JS):
```javascript
function renderOrderCard(o) {
  var priColor = PRIORITY_COLORS[o.priority] || PRIORITY_COLORS.low;
  var priLabel = PRIORITY_LABELS[o.priority] || o.priority.toUpperCase();
  var meta = [o.client, o.project].filter(Boolean).join(' · ');
  return '<div class="px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer ' +
         'border-b border-gray-50 dark:border-gray-700/50 transition-colors"' +
         ' onclick="openOrderDrawer(' + o.id + ', ' + JSON.stringify(o.title) + ', \'' + o.path + '\')">' +
         '<div class="flex items-start justify-between gap-2 mb-1">' +
         '<p class="text-sm font-medium text-gray-900 dark:text-white truncate flex-1">' + o.title + '</p>' +
         '<span class="text-xs text-gray-400 shrink-0">' + (o.due_date || '') + '</span>' +
         '</div>' +
         (meta ? '<p class="text-xs text-blue-600 dark:text-blue-400 truncate mb-1.5">' + meta + '</p>' : '') +
         '<div class="flex items-center gap-1.5 flex-wrap">' +
         '<span class="text-xs text-gray-500 dark:text-gray-400">' + o.status + '</span>' +
         '<span class="text-xs font-semibold px-1.5 py-0.5 rounded-full ' + priColor + '">' + priLabel + '</span>' +
         (o.assignee ? '<span class="text-xs text-gray-400 dark:text-gray-500 ml-auto">담당: ' + o.assignee + '</span>' : '') +
         '</div>' +
         '</div>';
}
```

---

## 4. UI Mockup

### 4.1 캘린더 그리드 (개선 후)

```
┌──────────────────────────────────────────────────────────┐
│  일    월    화    수    목    금    토                    │
├──────────────────────────────────────────────────────────┤
│  [연한회색 - 다른달]   1    2    3    4    5              │
│                   [흰배경] [흰배경] [주황배경D-7]...      │
│                                   ● RFQ-123              │
│                                   ● Valve-456            │
│                                   +1 more                │
├──────────────────────────────────────────────────────────┤
│  8    9    10   11   12   13   14                        │
│ [연파랑=1건] [중파랑=3건] [빨강=overdue]                  │
│  ● Pump    ● 3건   ● 긴급주문                             │
└──────────────────────────────────────────────────────────┘
```

### 4.2 사이드 패널 카드 (개선 후)

```
┌──────────────────────────────────┐
│ 2월 15일 마감 (3건)          [✕] │
├──────────────────────────────────┤
│ Valve Assembly        02/15      │
│ ABC Corp · Site-A               │
│ confirmed  [HIGH]  담당: 홍길동  │
├──────────────────────────────────┤
│ Pump Unit             02/15      │
│ XYZ Ltd                         │
│ procuring  [URGENT]             │
└──────────────────────────────────┘
```

---

## 5. Implementation Order

1. `calendar_controller.rb` — 조회 범위 grid_start..grid_end + @stats 분리
2. `index.html.erb` — 뷰 상단 `today` 변수 이동 (중복 제거)
3. `index.html.erb` — heatmap_bg / risk_bg ERB 로직 추가
4. `index.html.erb` — 날짜 셀 클래스 적용
5. `index.html.erb` — data-orders JSON 필드 확장
6. `index.html.erb` — JavaScript `renderOrderCard` 함수 교체

---

## 6. Completion Criteria

| # | Criteria | 검증 방법 |
|---|----------|-----------|
| 1 | 납기 건수 히트맵 4단계 적용 | 뷰 HTML 확인 |
| 2 | overdue/D-7 위험도 배경색 우선 적용 | ERB 로직 확인 |
| 3 | 사이드 패널 카드: client/project/assignee/due_date 포함 | JS renderOrderCard 확인 |
| 4 | 컨트롤러 조회 범위 grid_start..grid_end | controller 쿼리 확인 |
| 5 | @stats는 해당 월 주문만 카운트 | controller 로직 확인 |
| 6 | Gap Analysis Match Rate >= 90% | gap-detector |

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
