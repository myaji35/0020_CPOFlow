# Design: calendar-ux

## 개요

캘린더 UX 개선 — 통계 바(FR-01) + 날짜 사이드 패널(FR-02) + 카드→드로어(FR-03) + 오늘 버튼(FR-04) + 하단 목록 배지(FR-05)

- **Plan**: `docs/01-plan/features/calendar-ux.plan.md`
- **작성일**: 2026-02-28

---

## 실측 확인 사항

| 항목 | 값 |
|------|-----|
| `openOrderDrawer(id, title, path)` | `app/views/layouts/application.html.erb` L152 전역 함수 |
| `due_badge(order)` | `app/helpers/application_helper.rb` L19 |
| `priority_badge(order)` | `app/helpers/application_helper.rb` L35 |
| `status_badge(order)` | `app/helpers/application_helper.rb` L47 |
| 컨트롤러 현재 includes | `:assignees` 만 |
| 컨트롤러 확장 대상 | `includes(:assignees, :client, :project)` |
| 날짜 셀 구조 | `div.min-h-24 border-b border-r` — JS용 data 속성 없음 |
| 하단 목록 | 상태 배지 + "보기" 링크만 있음 |

---

## 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `app/controllers/calendar_controller.rb` | 수정 | includes 보강 + @stats |
| `app/views/calendar/index.html.erb` | 수정 | FR-01~05 전체 |

---

## FR-01: 월별 통계 바

### 컨트롤러 변경

```ruby
# app/controllers/calendar_controller.rb
class CalendarController < ApplicationController
  def index
    @month  = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    @orders = Order.where(due_date: @month..@month.end_of_month)
                   .includes(:assignees, :client, :project)
                   .by_due_date

    today = Date.today
    @stats = {
      total:   @orders.count,
      overdue: @orders.count { |o| o.due_date < today },
      urgent:  @orders.count { |o| o.due_date >= today && o.due_date <= today + 7 },
      normal:  @orders.count { |o| o.due_date > today + 7 }
    }
  end
end
```

### 통계 바 ERB (헤더 `</div>` 직후, 캘린더 그리드 위)

```erb
<%# FR-01: 월별 납기 통계 바 %>
<div class="grid grid-cols-4 gap-3">
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 text-center">
    <p class="text-2xl font-bold text-gray-900 dark:text-white"><%= @stats[:total] %></p>
    <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">총 마감</p>
  </div>
  <div class="bg-red-50 dark:bg-red-900/20 rounded-xl border border-red-100 dark:border-red-800 p-4 text-center">
    <p class="text-2xl font-bold text-red-600 dark:text-red-400"><%= @stats[:overdue] %></p>
    <p class="text-xs text-red-500 dark:text-red-400 mt-1">지연</p>
  </div>
  <div class="bg-orange-50 dark:bg-orange-900/20 rounded-xl border border-orange-100 dark:border-orange-800 p-4 text-center">
    <p class="text-2xl font-bold text-orange-600 dark:text-orange-400"><%= @stats[:urgent] %></p>
    <p class="text-xs text-orange-500 dark:text-orange-400 mt-1">D-7 이내</p>
  </div>
  <div class="bg-green-50 dark:bg-green-900/20 rounded-xl border border-green-100 dark:border-green-800 p-4 text-center">
    <p class="text-2xl font-bold text-green-600 dark:text-green-400"><%= @stats[:normal] %></p>
    <p class="text-xs text-green-500 dark:text-green-400 mt-1">정상</p>
  </div>
</div>
```

---

## FR-04: 오늘 버튼

헤더 네비게이션 영역 (`< YYYY년 MM월 >`) 에 "오늘" 버튼 추가:

```erb
<%# 기존 %>
<div class="flex items-center gap-2">
  <%= link_to calendar_path(month: (@month - 1.month)...), ... %>
  <span ...><%= @month.strftime("%Y년 %m월") %></span>
  <%= link_to calendar_path(month: (@month + 1.month)...), ... %>
</div>

<%# 변경: "오늘" 버튼 추가 %>
<div class="flex items-center gap-2">
  <%= link_to "오늘", calendar_path,
      class: "text-xs px-3 py-1.5 rounded-lg border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors" %>
  <%= link_to calendar_path(month: (@month - 1.month).strftime("%Y-%m-%d")), ... %>
  <span ...>...</span>
  <%= link_to calendar_path(month: (@month + 1.month).strftime("%Y-%m-%d")), ... %>
</div>
```

---

## FR-02 + FR-03: 날짜 셀 + 사이드 패널

### 날짜 셀 변경 (data 속성 추가 + 카드 onclick)

```erb
<%
  # orders JSON for JS panel
  day_orders_json = day_orders.map { |o|
    {
      id:       o.id,
      title:    o.title,
      path:     order_path(o),
      status:   Order::STATUS_LABELS[o.status],
      priority: o.priority,
      due_date: o.due_date.strftime("%m/%d")
    }
  }.to_json
%>
<div class="min-h-24 border-b border-r border-gray-50 dark:border-gray-700 p-2 cursor-pointer
            <%= is_current_month ? 'bg-white dark:bg-gray-800' : 'bg-gray-50 dark:bg-gray-700/30' %>
            <%= is_today ? 'ring-2 ring-inset ring-primary/30' : '' %>
            hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors"
     data-calendar-date="<%= date.strftime('%Y-%m-%d') %>"
     data-orders="<%= html_escape(day_orders_json) %>">
  <div class="flex justify-between items-center mb-1">
    <span class="text-xs font-medium <%= is_today ? 'w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center' : is_current_month ? 'text-gray-700 dark:text-gray-300' : 'text-gray-300 dark:text-gray-600' %>">
      <%= date.day %>
    </span>
  </div>
  <% day_orders.first(3).each do |order| %>
    <%# FR-03: onclick → openOrderDrawer %>
    <div class="block text-xs truncate px-1.5 py-0.5 rounded mb-0.5 cursor-pointer <%= case order.priority
      when 'urgent' then 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400'
      when 'high'   then 'bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-400'
      else               'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400'
      end %>"
         onclick="event.stopPropagation(); openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
      <%= order.title %>
    </div>
  <% end %>
  <% if day_orders.size > 3 %>
    <span class="text-xs text-gray-400 dark:text-gray-500">+<%= day_orders.size - 3 %> more</span>
  <% end %>
</div>
```

### 사이드 패널 HTML (캘린더 그리드 div 뒤에 삽입)

```erb
<%# FR-02: 날짜 사이드 패널 %>
<div id="calendar-panel-overlay" class="fixed inset-0 z-40 hidden"></div>
<div id="calendar-side-panel"
     class="fixed top-0 right-0 h-full w-80 bg-white dark:bg-gray-900 border-l border-gray-200 dark:border-gray-700 shadow-xl z-50 transform translate-x-full transition-transform duration-200 flex flex-col">
  <div class="flex items-center justify-between px-4 py-4 border-b border-gray-100 dark:border-gray-700">
    <h3 id="panel-date-title" class="text-sm font-semibold text-gray-900 dark:text-white"></h3>
    <button id="calendar-panel-close"
            class="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors">
      <svg class="w-4 h-4 text-gray-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    </button>
  </div>
  <div id="panel-orders-list" class="flex-1 overflow-y-auto py-2"></div>
</div>
```

### 사이드 패널 JS (DOMContentLoaded 내)

```javascript
// ── FR-02: 날짜 사이드 패널 ──────────────────────────────
const sidePanel  = document.getElementById('calendar-side-panel');
const panelTitle = document.getElementById('panel-date-title');
const panelList  = document.getElementById('panel-orders-list');
const panelClose = document.getElementById('calendar-panel-close');
const overlay    = document.getElementById('calendar-panel-overlay');

const PRIORITY_COLORS = {
  urgent: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  high:   'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
  medium: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  low:    'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
};

function openDatePanel(dateStr, orders) {
  panelTitle.textContent = dateStr + ' 마감 (' + orders.length + '건)';
  if (orders.length === 0) {
    panelList.innerHTML = '<p class="text-xs text-gray-400 text-center py-8">마감 주문 없음</p>';
  } else {
    panelList.innerHTML = orders.map(function(o) {
      const priColor = PRIORITY_COLORS[o.priority] || PRIORITY_COLORS.low;
      return '<div class="flex items-center gap-3 px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer transition-colors border-b border-gray-50 dark:border-gray-700/50"' +
             ' onclick="openOrderDrawer(' + o.id + ', ' + JSON.stringify(o.title) + ', \'' + o.path + '\')">' +
             '<div class="flex-1 min-w-0">' +
             '<p class="text-sm font-medium text-gray-900 dark:text-white truncate">' + o.title + '</p>' +
             '<p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">' + o.status + '</p>' +
             '</div>' +
             '<span class="text-xs font-semibold px-2 py-0.5 rounded-full ' + priColor + '">' + o.priority.toUpperCase() + '</span>' +
             '</div>';
    }).join('');
  }
  overlay.classList.remove('hidden');
  requestAnimationFrame(function() {
    sidePanel.classList.remove('translate-x-full');
  });
}

function closeDatePanel() {
  sidePanel.classList.add('translate-x-full');
  overlay.classList.add('hidden');
}

// 날짜 셀 클릭
document.querySelectorAll('[data-calendar-date]').forEach(function(cell) {
  cell.addEventListener('click', function() {
    const orders = JSON.parse(cell.dataset.orders || '[]');
    openDatePanel(cell.dataset.calendarDate, orders);
  });
});

panelClose.addEventListener('click', closeDatePanel);
overlay.addEventListener('click', closeDatePanel);
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') closeDatePanel();
});
```

---

## FR-05: 하단 목록 배지 강화

기존 `<div class="flex items-center gap-3 px-5 py-3 ...">` 내부 변경:

```erb
<%# 기존: status 배지 + "보기" 링크 %>
<%# 변경: 발주처/프로젝트 추가, priority_badge + due_badge 추가, 드로어 연동 %>
<div class="flex items-center justify-between px-5 py-3
            hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors cursor-pointer"
     onclick="openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
  <div class="flex items-center gap-3">
    <div class="text-center w-10 shrink-0">
      <p class="text-lg font-bold text-gray-900 dark:text-white"><%= order.due_date.day %></p>
      <p class="text-xs text-gray-400 dark:text-gray-500"><%= order.due_date.strftime("%a") %></p>
    </div>
    <div class="min-w-0">
      <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= order.title %></p>
      <div class="flex items-center gap-1.5 mt-0.5 flex-wrap">
        <% if order.client %>
          <span class="text-xs text-blue-600 dark:text-blue-400"><%= order.client.name %></span>
        <% elsif order.customer_name.present? %>
          <span class="text-xs text-gray-500 dark:text-gray-400"><%= order.customer_name %></span>
        <% end %>
        <% if order.project %>
          <span class="text-xs text-green-600 dark:text-green-400"><%= order.project.name %></span>
        <% end %>
      </div>
    </div>
  </div>
  <div class="flex items-center gap-2 shrink-0">
    <%= status_badge(order) %>
    <%= priority_badge(order) %>
    <%= due_badge(order) %>
  </div>
</div>
```

---

## 구현 순서

1. `calendar_controller.rb` — includes 보강 + @stats
2. `calendar/index.html.erb` — FR-04 오늘 버튼
3. `calendar/index.html.erb` — FR-01 통계 바
4. `calendar/index.html.erb` — FR-02 사이드 패널 HTML
5. `calendar/index.html.erb` — 날짜 셀 data 속성 + FR-03 카드 onclick
6. `calendar/index.html.erb` — FR-05 하단 목록 배지
7. `calendar/index.html.erb` — FR-02 사이드 패널 JS
8. rubocop 체크

---

## 완료 기준

- [ ] 통계 바 4개 카드 표시 (총/지연/D-7/정상)
- [ ] 날짜 클릭 → 우측 사이드 패널 (해당 날 주문 목록)
- [ ] 패널 내 order 클릭 → openOrderDrawer 실행
- [ ] 캘린더 카드 클릭 → openOrderDrawer 실행 (셀 클릭과 충돌 없음)
- [ ] "오늘" 버튼 → 오늘 달로 이동
- [ ] 하단 목록 배지 (status + priority + due_badge) 표시
- [ ] Gap Analysis Match Rate ≥ 90%
