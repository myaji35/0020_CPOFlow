# notification-ux Design

## 1. Overview

**Feature**: notification-ux (알림 센터 UX 개선)
**Design Date**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/notification-ux.plan.md`
**Implementation Target**: `shared/_header.html.erb`, `notifications/index.html.erb`

---

## 2. Current State Analysis

### 2.1 shared/_header.html.erb (현재)

```erb
<!-- 알림 배지 -->
<% unread_count = current_user.notifications.unread.count rescue 0 %>
<%= link_to notifications_path, class: "relative flex items-center ...", title: "알림" do %>
  <svg ...벨 아이콘...></svg>
  <% if unread_count > 0 %>
    <span class="absolute -top-1 -right-1 bg-primary text-white ...">
      <%= [unread_count, 9].min %><%= unread_count > 9 ? "+" : "" %>
    </span>
  <% end %>
<% end %>
```

**문제**: `link_to notifications_path` → 클릭 시 전체 페이지 이동

### 2.2 notifications/index.html.erb (현재)

- 읽음/안읽음 구분: `opacity-60` 클래스만 (약함)
- Order 링크: `link_to "주문 보기 →", order_path(n.notifiable)` → 전체 페이지 이동
- 타입 필터 탭: 없음
- `system` 타입 아이콘: `else` 분기로 벨 아이콘 재사용 (미구현)

---

## 3. Functional Requirements Design

### FR-01: 헤더 알림 드롭다운 패널

#### 3.1 HTML 구조

```erb
<%# shared/_header.html.erb — 알림 배지 영역 교체 %>

<% unread_count = current_user.notifications.unread.count rescue 0 %>
<% recent_notifications = current_user.notifications.recent.includes(:notifiable).limit(10) rescue [] %>

<div id="notification-bell" class="relative">
  <%# 벨 버튼 %>
  <button onclick="toggleNotificationPanel()"
          class="relative flex items-center text-gray-500 dark:text-gray-400 hover:text-primary transition-colors"
          title="알림">
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
      <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
    </svg>
    <% if unread_count > 0 %>
      <span class="absolute -top-1 -right-1 bg-primary text-white text-xs rounded-full w-4 h-4 flex items-center justify-center font-bold leading-none">
        <%= [unread_count, 9].min %><%= unread_count > 9 ? "+" : "" %>
      </span>
    <% end %>
  </button>

  <%# 드롭다운 패널 %>
  <div id="notification-panel"
       class="hidden absolute right-0 top-8 w-80 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-lg z-50 overflow-hidden">

    <%# 패널 헤더 %>
    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100 dark:border-gray-700">
      <span class="text-sm font-semibold text-gray-900 dark:text-white">알림</span>
      <div class="flex items-center gap-3">
        <% if unread_count > 0 %>
          <%= button_to "모두 읽음", read_all_notifications_path, method: :patch,
              class: "text-xs text-primary hover:underline bg-transparent border-0 cursor-pointer" %>
        <% end %>
        <%= link_to notifications_path,
            class: "text-xs text-gray-400 hover:text-primary transition-colors" do %>
          전체 보기 →
        <% end %>
      </div>
    </div>

    <%# 알림 목록 (최근 10개) %>
    <div class="max-h-96 overflow-y-auto">
      <% if recent_notifications.any? %>
        <% recent_notifications.each do |n| %>
          <div class="flex items-start gap-3 px-4 py-3 border-b border-gray-50 dark:border-gray-700/50
                      hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors
                      <%= n.read? ? 'bg-white dark:bg-gray-800' : 'bg-blue-50 dark:bg-blue-900/20' %>"
               <% if n.notifiable.is_a?(Order) %>
               onclick="toggleNotificationPanel(); openOrderDrawer(<%= n.notifiable.id %>, <%= n.notifiable.title.to_json %>, '<%= order_path(n.notifiable) %>')"
               style="cursor:pointer"
               <% end %>>

            <%# 읽음 상태 점 %>
            <div class="flex-shrink-0 flex items-center pt-1">
              <% if n.read? %>
                <div class="w-1.5 h-1.5 rounded-full bg-transparent"></div>
              <% else %>
                <div class="w-1.5 h-1.5 rounded-full bg-primary"></div>
              <% end %>
            </div>

            <%# 타입 아이콘 %>
            <div class="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0
              <%= notification_icon_bg(n.notification_type) %>">
              <%= notification_icon_svg(n.notification_type) %>
            </div>

            <%# 내용 %>
            <div class="flex-1 min-w-0">
              <p class="text-xs <%= n.read? ? 'font-medium text-gray-700 dark:text-gray-300' : 'font-semibold text-gray-900 dark:text-white' %> leading-snug">
                <%= n.title %>
              </p>
              <span class="text-xs text-gray-400 dark:text-gray-500">
                <%= n.created_at.strftime("%m/%d %H:%M") %>
              </span>
            </div>
          </div>
        <% end %>
      <% else %>
        <div class="p-8 text-center">
          <svg class="w-8 h-8 mx-auto text-gray-200 dark:text-gray-600 mb-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
            <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
          </svg>
          <p class="text-xs text-gray-400 dark:text-gray-500">새 알림이 없습니다</p>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

#### 3.2 JavaScript (패널 안에 inline)

```javascript
function toggleNotificationPanel() {
  const panel = document.getElementById('notification-panel');
  panel.classList.toggle('hidden');
}

// 외부 클릭 닫기
document.addEventListener('click', function(e) {
  const bell = document.getElementById('notification-bell');
  const panel = document.getElementById('notification-panel');
  if (panel && !panel.classList.contains('hidden') && bell && !bell.contains(e.target)) {
    panel.classList.add('hidden');
  }
});

// Escape 닫기
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    document.getElementById('notification-panel')?.classList.add('hidden');
  }
});
```

---

### FR-02: 읽음 상태 시각화 (notifications/index.html.erb)

#### Before (현재)
```erb
<div class="flex items-start gap-3 ... <%= n.read? ? 'opacity-60' : '' %>">
```

#### After (변경)

```erb
<div class="flex items-start gap-3 px-5 py-4 border-b border-gray-50 dark:border-gray-700
            hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors
            <%= n.read? ? '' : 'bg-blue-50 dark:bg-blue-900/20' %>"
     ...>

  <%# 읽음 상태 점 (좌측) %>
  <div class="flex-shrink-0 flex items-center pt-2">
    <div class="w-1.5 h-1.5 rounded-full <%= n.read? ? 'bg-transparent' : 'bg-primary' %>"></div>
  </div>

  <%# 타입 아이콘 (기존 유지, system 추가) %>
  ...
</div>
```

---

### FR-03: openOrderDrawer 연동 (notifications/index.html.erb)

#### Before
```erb
<% if n.notifiable.is_a?(Order) %>
  <%= link_to "주문 보기 →", order_path(n.notifiable),
      class: "text-xs text-primary hover:underline mt-1 inline-block" %>
<% end %>
```

#### After
```erb
<% if n.notifiable.is_a?(Order) %>
  <button onclick="openOrderDrawer(<%= n.notifiable.id %>, <%= n.notifiable.title.to_json %>, '<%= order_path(n.notifiable) %>')"
          class="text-xs text-primary hover:underline mt-1 cursor-pointer bg-transparent border-0 p-0">
    주문 보기 →
  </button>
<% end %>
```

---

### FR-04: 타입 필터 탭 (notifications/index.html.erb)

#### HTML

```erb
<%# 타입 필터 탭 %>
<div class="flex gap-1 border-b border-gray-100 dark:border-gray-700 mb-0 px-0"
     id="notification-tabs">
  <% [
    ['all',            '전체'],
    ['due_date',       '납기'],
    ['status_changed', '상태변경'],
    ['assigned',       '배정']
  ].each do |type, label| %>
    <button onclick="filterNotifications('<%= type %>')"
            id="tab-<%= type %>"
            class="px-4 py-2.5 text-sm font-medium transition-colors border-b-2
                   <%= type == 'all' ? 'border-primary text-primary' : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300' %>">
      <%= label %>
    </button>
  <% end %>
</div>

<%# 알림 목록에 data-type 속성 추가 %>
<div class="notification-item" data-type="<%= n.notification_type %>">
  ...
</div>
```

#### JavaScript

```javascript
function filterNotifications(type) {
  // 탭 활성화
  document.querySelectorAll('#notification-tabs button').forEach(btn => {
    btn.classList.remove('border-primary', 'text-primary');
    btn.classList.add('border-transparent', 'text-gray-500');
  });
  const activeTab = document.getElementById('tab-' + type);
  activeTab.classList.add('border-primary', 'text-primary');
  activeTab.classList.remove('border-transparent', 'text-gray-500');

  // 항목 필터
  document.querySelectorAll('.notification-item').forEach(item => {
    if (type === 'all' || item.dataset.type === type) {
      item.style.display = '';
    } else {
      item.style.display = 'none';
    }
  });
}
```

---

### FR-05: system 타입 아이콘

`notifications/index.html.erb` 타입 분기에 `system` 추가:

```erb
<%# 아이콘 색상 %>
<% case n.notification_type
   when 'due_date'       then 'bg-red-100 dark:bg-red-900/30' ... 'text-red-600'
   when 'status_changed' then 'bg-blue-100 dark:bg-blue-900/30' ... 'text-blue-600'
   when 'assigned'       then 'bg-green-100 dark:bg-green-900/30' ... 'text-green-600'
   when 'system'         then 'bg-purple-100 dark:bg-purple-900/30' ... 'text-purple-600'   ← 추가
   else                       'bg-gray-100 dark:bg-gray-700' ... 'text-gray-500'
   end %>

<%# system 아이콘 SVG %>
<% when 'system' %>
  <circle cx="12" cy="12" r="10"/>
  <line x1="12" y1="8" x2="12" y2="12"/>
  <line x1="12" y1="16" x2="12.01" y2="16"/>
```

---

## 4. Helper Methods (선택적 리팩터링)

드롭다운과 index에서 동일한 아이콘 로직이 반복되므로 ApplicationHelper에 추출 가능:

```ruby
# app/helpers/application_helper.rb (선택적)
def notification_icon_bg(type)
  case type
  when 'due_date'       then 'bg-red-100 dark:bg-red-900/30'
  when 'status_changed' then 'bg-blue-100 dark:bg-blue-900/30'
  when 'assigned'       then 'bg-green-100 dark:bg-green-900/30'
  when 'system'         then 'bg-purple-100 dark:bg-purple-900/30'
  else                       'bg-gray-100 dark:bg-gray-700'
  end
end
```

> **구현 결정**: Helper 추출 대신 인라인 ERB case로 직접 구현. 두 파일이 동일한 패턴을 공유하지만, 각각 독립적으로 수정 가능하도록 중복 허용.

---

## 5. Implementation Order

```
Step 1: shared/_header.html.erb
  - link_to → button + 드롭다운 패널 div
  - JS 3개 함수 (toggle / 외부클릭 / Escape)

Step 2: notifications/index.html.erb
  - 타입 필터 탭 추가 (FR-04)
  - 읽음 상태 시각화 교체 (FR-02)
  - openOrderDrawer 연동 (FR-03)
  - system 타입 아이콘 추가 (FR-05)
  - data-type 속성 + JS filterNotifications 함수
```

---

## 6. File Summary

| File | Lines (현재) | 변경 내용 |
|------|:---:|-------|
| `app/views/shared/_header.html.erb` | 41 | L26-33 교체 → 드롭다운 패널 + JS (약 +60줄) |
| `app/views/notifications/index.html.erb` | 86 | 필터 탭 + 읽음 시각화 + 드로어 + system (약 +30줄) |

---

## 7. Completion Criteria

| # | Criteria | FR |
|---|----------|----|
| 1 | 헤더 벨 클릭 → 드롭다운 패널 (최근 10개) | FR-01 |
| 2 | 패널 외부 클릭 / Escape → 닫힘 | FR-01 |
| 3 | 드롭다운에서 Order 항목 클릭 → openOrderDrawer | FR-01, FR-03 |
| 4 | 안읽음 = 파란 점 + bg-blue-50 배경 / 읽음 = 일반 | FR-02 |
| 5 | index에서 Order 링크 → openOrderDrawer 버튼 | FR-03 |
| 6 | 타입 필터 탭 (전체/납기/상태변경/배정) JS 필터 동작 | FR-04 |
| 7 | system 타입 아이콘 (보라색) 표시 | FR-05 |
| 8 | Gap Analysis Match Rate >= 90% | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial design | bkit:pdca |
