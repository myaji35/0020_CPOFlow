# Feature Design: kanban-inbox-grouping

## Architecture

### 변경 범위
1. `KanbanController#index` — Inbox 컬럼 데이터 그룹핑 로직 추가
2. `app/views/kanban/index.html.erb` — Inbox 컬럼 렌더링 수정
3. `app/views/kanban/_card.html.erb` — 스레드 뱃지 추가

---

## KanbanController#index 변경

### 현재
```ruby
@columns = Order::KANBAN_COLUMNS.map do |status|
  orders = Order.where(status: status).by_due_date.includes(...)
  [status, orders]
end.to_h
```

### 변경 후
```ruby
@columns = Order::KANBAN_COLUMNS.map do |status|
  orders = Order.where(status: status).by_due_date.includes(:assignees, :tasks, :user)
  [status, orders]
end.to_h

# Inbox 전용 그룹핑
inbox_orders = @columns["inbox"] || []
@inbox_grouped = build_inbox_groups(inbox_orders)
```

### build_inbox_groups 헬퍼 메서드 (private)
```ruby
def build_inbox_groups(orders)
  # reference_no 있는 것: 그룹핑 (최신 1개 대표 + 나머지 count)
  # reference_no 없는 것: 단건 그대로
  groups = orders.group_by { |o| o.reference_no.presence || "single_#{o.id}" }

  groups.map do |key, group_orders|
    representative = group_orders.first  # by_due_date로 정렬된 상태에서 첫 번째
    thread_count   = group_orders.size
    { order: representative, thread_count: thread_count, is_thread: thread_count > 1 }
  end
end
```

---

## View: kanban/index.html.erb 변경

Inbox 컬럼 렌더링 부분만 분기:

```erb
<% if status == "inbox" %>
  <% @inbox_grouped.each do |group| %>
    <%= render "kanban/card",
               order: group[:order],
               prev_status: prev_stat,
               next_status: next_stat,
               thread_count: group[:thread_count],
               is_thread: group[:is_thread] %>
  <% end %>
<% else %>
  <% orders.each do |order| %>
    <%= render "kanban/card", order: order, prev_status: prev_stat, next_status: next_stat %>
  <% end %>
<% end %>
```

### 컬럼 카운트 배지
- Inbox: `@inbox_grouped.size` (그룹 수)
- 기타: `orders.count` (기존)

---

## View: kanban/_card.html.erb 변경

스레드 뱃지 추가 (카드 제목 아래):

```erb
<% thread_count = local_assigns[:thread_count] || 1 %>
<% is_thread    = local_assigns[:is_thread]    || false %>

<%# 스레드 뱃지 — is_thread 일 때만 표시 %>
<% if is_thread %>
  <div class="inline-flex items-center gap-1 text-xs text-accent bg-blue-50 dark:bg-blue-900/30
              px-1.5 py-0.5 rounded-full mb-1.5">
    <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
    </svg>
    스레드 <%= thread_count %>건
  </div>
<% end %>
```

위치: 제목(h4) 바로 아래, 발주처/현장 뱃지 위

---

## 필터 호환성

기존 JS 필터(`applyFilters`)는 `[data-order-id]` 카드에 적용됨.
그룹 대표 카드도 동일 구조이므로 **변경 없이 호환**.

단, `@inbox_grouped.size` 기준으로 컬럼 카운트를 서버에서 렌더링하므로
JS `updateCounts()`와 불일치 방지를 위해 Inbox 컬럼 카운트는
그룹 수를 data 속성으로 전달:

```html
<span class="column-count ..."><%= status == "inbox" ? @inbox_grouped.size : orders.count %></span>
```

---

## Data Flow

```
KanbanController#index
  └─ Order.where(status: :inbox).by_due_date.includes(...)
       └─ build_inbox_groups
            ├─ group_by reference_no
            └─ [{order: representative, thread_count: N, is_thread: true/false}]
                  └─ render _card (thread_count, is_thread locals 전달)
```

---

## 구현 순서

1. `KanbanController` — `build_inbox_groups` private 메서드 추가 + `@inbox_grouped` 할당
2. `kanban/index.html.erb` — Inbox 분기 렌더링 + 카운트 배지 수정
3. `kanban/_card.html.erb` — 스레드 뱃지 HTML 추가
4. 브라우저 확인 (Playwright)
