# drawer-ux Design

## 1. Overview

**Feature**: drawer-ux (주문 드로어 UX 개선)
**Design Date**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/drawer-ux.plan.md`
**Implementation Target**:
- `app/views/orders/_drawer_content.html.erb`
- `app/views/layouts/application.html.erb`

---

## 2. Current State Analysis

### 2.1 _drawer_content.html.erb (현재, 352줄)

단일 스크롤 구조:
```
[메타 정보] → [담당자+스테이지이동] → [이메일원문] → [태스크] → [코멘트] → [활동로그]
```

### 2.2 layouts/application.html.erb 드로어 헤더 (L129-142)

```html
<div class="flex items-center justify-between px-6 py-4 ...">
  <div id="drawer-title" ...></div>
  <div class="flex items-center gap-2">
    <a id="drawer-open-link" ...>전체 화면</a>
    <button onclick="closeOrderDrawer()">✕</button>
  </div>
</div>
```

### 2.3 Key Facts (실측)

- `priority` enum: `low(0)`, `medium(1)`, `high(2)`, `urgent(3)` — default: medium
- `KANBAN_COLUMNS`: `%w[inbox reviewing quoted confirmed procuring qa delivered]`
- `move_status_order_path(order)` PATCH — `params[:status]` 받아 상태 변경 + Activity 기록
- `quick_update_order_path(order)` PATCH — `order[priority]` 포함 (order_params에 `:priority` 있음)
- `STATUS_LABELS`: inbox→"Inbox", reviewing→"Under Review", ... delivered→"Delivered"

---

## 3. Functional Requirements Design

### FR-01: 탭 구조 (orders/_drawer_content.html.erb)

#### 3.1 탭 바 HTML

```erb
<%# 탭 바 — 드로어 콘텐츠 최상단 %>
<div class="flex border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 sticky top-0 z-10"
     id="drawer-tabs-<%= order.id %>">
  <% [
    ['detail',  '상세',     'M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2'],
    ['tasks',   '태스크',   'M9 11 12 14 22 4 M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11'],
    ['comments','코멘트',   'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'],
    ['history', '히스토리', 'M22 12 18 12 15 21 9 3 6 12 2 12']
  ].each_with_index do |(tab_id, label, _icon), i| %>
    <button onclick="switchDrawerTab('<%= order.id %>', '<%= tab_id %>')"
            id="drawer-tab-<%= order.id %>-<%= tab_id %>"
            class="flex items-center gap-1.5 px-4 py-3 text-sm font-medium transition-colors border-b-2
                   <%= i == 0 ? 'border-primary text-primary' : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300' %>">
      <%= label %>
      <%# 코멘트 탭 카운트 배지 %>
      <% if tab_id == 'comments' && comments.any? %>
        <span class="text-xs bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 px-1.5 py-0.5 rounded-full"><%= comments.count %></span>
      <% end %>
      <%# 태스크 탭 카운트 배지 %>
      <% if tab_id == 'tasks' && tasks.any? %>
        <span class="text-xs bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 px-1.5 py-0.5 rounded-full"><%= tasks.count %></span>
      <% end %>
    </button>
  <% end %>
</div>
```

#### 3.2 탭 패널 구조

각 섹션을 `id="drawer-panel-{order.id}-{tab_id}"` 로 감싸고,
기본은 `detail`만 표시, 나머지는 `hidden`:

```erb
<%# 상세 탭 패널 %>
<div id="drawer-panel-<%= order.id %>-detail" class="p-6 space-y-6">
  <%# 기존 메타 정보 + 담당자 + 스테이지이동 + 이메일원문 %>
</div>

<%# 태스크 탭 패널 %>
<div id="drawer-panel-<%= order.id %>-tasks" class="p-6 hidden">
  <%# 기존 태스크 체크리스트 (Turbo Frame 유지) %>
</div>

<%# 코멘트 탭 패널 %>
<div id="drawer-panel-<%= order.id %>-comments" class="p-6 hidden">
  <%# 기존 코멘트 (Turbo Stream 유지) %>
</div>

<%# 히스토리 탭 패널 %>
<div id="drawer-panel-<%= order.id %>-history" class="p-6 hidden">
  <%# 기존 활동 로그 타임라인 %>
</div>
```

#### 3.3 switchDrawerTab() JavaScript

```javascript
function switchDrawerTab(orderId, tabId) {
  var panels = ['detail', 'tasks', 'comments', 'history'];
  panels.forEach(function(p) {
    var panel = document.getElementById('drawer-panel-' + orderId + '-' + p);
    var tab   = document.getElementById('drawer-tab-' + orderId + '-' + p);
    if (!panel || !tab) return;
    if (p === tabId) {
      panel.classList.remove('hidden');
      tab.classList.add('border-primary', 'text-primary');
      tab.classList.remove('border-transparent', 'text-gray-500', 'dark:text-gray-400');
    } else {
      panel.classList.add('hidden');
      tab.classList.remove('border-primary', 'text-primary');
      tab.classList.add('border-transparent', 'text-gray-500', 'dark:text-gray-400');
    }
  });
}
```

`<script>` 블록은 `_drawer_content.html.erb` 하단에 인라인 추가.

---

### FR-02: 드로어 헤더 빠른 상태 변경 (layouts/application.html.erb)

#### 3.4 현재 상태 → 다음 상태 계산

`KANBAN_COLUMNS = %w[inbox reviewing quoted confirmed procuring qa delivered]`

다음 스테이지 버튼은 `openOrderDrawer` 호출 시 `data` 속성으로 현재 status 전달.

#### 3.5 헤더 HTML 변경

```html
<!-- Before -->
<div id="drawer-title" ...></div>
<div class="flex items-center gap-2">
  <a id="drawer-open-link" ...>전체 화면</a>
  <button onclick="closeOrderDrawer()">✕</button>
</div>

<!-- After -->
<div class="flex-1 min-w-0 flex items-center gap-2">
  <div id="drawer-title" ...></div>
  <!-- 현재 상태 배지 (JS로 주입) -->
  <span id="drawer-status-badge" class="hidden"></span>
</div>
<div class="flex items-center gap-2 flex-shrink-0">
  <!-- 다음 단계 버튼 (JS로 주입, delivered이면 hidden) -->
  <form id="drawer-next-status-form" method="post" class="hidden">
    <input type="hidden" name="_method" value="patch">
    <input type="hidden" name="authenticity_token" id="drawer-csrf-token">
    <input type="hidden" name="status" id="drawer-next-status-value">
    <button type="submit"
            id="drawer-next-status-btn"
            class="flex items-center gap-1.5 text-xs font-medium px-2.5 py-1.5 rounded-lg
                   bg-accent text-white hover:bg-accent/90 transition-colors">
      <span id="drawer-next-status-label"></span>
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="9 18 15 12 9 6"/>
      </svg>
    </button>
  </form>
  <a id="drawer-open-link" href="#" ...>전체 화면</a>
  <button onclick="closeOrderDrawer()">✕</button>
</div>
```

#### 3.6 openOrderDrawer() 확장

```javascript
function openOrderDrawer(orderId, orderTitle, orderPath, orderStatus) {
  // ... 기존 코드 ...

  // 다음 단계 버튼 세팅
  var columns = ['inbox','reviewing','quoted','confirmed','procuring','qa','delivered'];
  var currentIdx = columns.indexOf(orderStatus || '');
  var nextStatusForm = document.getElementById('drawer-next-status-form');
  var nextStatusBtn  = document.getElementById('drawer-next-status-btn');
  var nextLabel      = document.getElementById('drawer-next-status-label');
  var nextInput      = document.getElementById('drawer-next-status-value');
  var csrfInput      = document.getElementById('drawer-csrf-token');
  var statusLabels = {
    inbox:'Inbox', reviewing:'Under Review', quoted:'Quoted',
    confirmed:'Order Confirmed', procuring:'Procuring', qa:'QA', delivered:'Delivered'
  };

  if (currentIdx >= 0 && currentIdx < columns.length - 1) {
    var nextStatus = columns[currentIdx + 1];
    nextLabel.textContent = statusLabels[nextStatus] || nextStatus;
    nextInput.value = nextStatus;
    // CSRF 토큰
    var csrfMeta = document.querySelector('meta[name="csrf-token"]');
    if (csrfMeta) csrfInput.value = csrfMeta.content;
    nextStatusForm.action = orderPath + '/move_status';
    nextStatusForm.classList.remove('hidden');
  } else {
    nextStatusForm.classList.add('hidden');
  }
}
```

`openOrderDrawer`는 4번째 인자 `orderStatus`를 받도록 시그니처 확장.
기존 호출처는 4번째 인자 없이 호출하면 `orderStatus = undefined` → 버튼 숨김 (안전).

드로어 본문 fetch 완료 후 현재 상태를 data 속성으로 읽는 방식도 가능하나,
호출 시점에 status를 직접 전달하는 방식이 더 단순하고 안정적.

---

### FR-03: 우선순위 인라인 변경 (orders/_drawer_content.html.erb)

#### 3.7 priority_badge → 클릭 드롭다운

상세 탭 패널 내 배지 영역:

```erb
<%# 기존 priority_badge(order) 대신 %>
<div class="relative inline-block" id="priority-dropdown-<%= order.id %>">
  <button onclick="togglePriorityDropdown('<%= order.id %>')"
          class="cursor-pointer">
    <%= priority_badge(order) %>
  </button>
  <div id="priority-menu-<%= order.id %>"
       class="hidden absolute left-0 top-full mt-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg z-20 py-1 w-36">
    <% [['low', '낮음'], ['medium', '보통'], ['high', '높음'], ['urgent', '긴급']].each do |val, label| %>
      <%= form_with url: quick_update_order_path(order), method: :patch, local: true do |f| %>
        <%= f.hidden_field :priority, value: val %>
        <button type="submit"
                class="w-full text-left px-3 py-1.5 text-xs hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors
                       <%= order.priority == val ? 'font-semibold text-primary' : 'text-gray-700 dark:text-gray-300' %>">
          <%= label %>
          <% if order.priority == val %>
            <span class="float-right">✓</span>
          <% end %>
        </button>
      <% end %>
    <% end %>
  </div>
</div>
```

#### 3.8 togglePriorityDropdown() JavaScript

```javascript
function togglePriorityDropdown(orderId) {
  var menu = document.getElementById('priority-menu-' + orderId);
  if (menu) menu.classList.toggle('hidden');
}
// 외부 클릭 닫기
document.addEventListener('click', function(e) {
  if (!e.target.closest('[id^="priority-dropdown-"]')) {
    document.querySelectorAll('[id^="priority-menu-"]').forEach(function(m) {
      m.classList.add('hidden');
    });
  }
});
```

---

## 4. Implementation Order

```
Step 1: layouts/application.html.erb
  - 드로어 헤더 HTML 구조 변경 (FR-02)
  - openOrderDrawer() 4번째 인자 + 다음 단계 버튼 로직 추가

Step 2: orders/_drawer_content.html.erb
  - 탭 바 추가 (FR-01)
  - 4개 탭 패널로 기존 섹션 분리 (FR-01)
  - priority 인라인 드롭다운 (FR-03)
  - switchDrawerTab() + togglePriorityDropdown() JS 추가
```

---

## 5. openOrderDrawer 시그니처 변경 영향

기존 호출처 조사:
- `shared/_header.html.erb` — 알림 드롭다운 (4번째 인자 없음 → undefined → 버튼 숨김 OK)
- `notifications/index.html.erb` — (4번째 인자 없음 → OK)
- `calendar/index.html.erb` — (4번째 인자 없음 → OK)
- `team/show.html.erb` — (4번째 인자 없음 → OK)
- `kanban/index.html.erb` 등 — 주요 화면에서 status 전달 추가 권장

> **구현 결정**: 기존 호출처 모두 4번째 인자 없이 유지 (backward compatible).
> kanban 카드에서 이미 status를 알고 있는 경우만 선택적으로 전달.

---

## 6. File Summary

| File | Lines (현재) | 변경 내용 |
|------|:---:|-------|
| `app/views/orders/_drawer_content.html.erb` | 352 | 탭 바 + 4패널 분리 + priority 드롭다운 + JS (~+60줄) |
| `app/views/layouts/application.html.erb` | ~200 | 드로어 헤더 + openOrderDrawer 확장 (~+25줄) |

---

## 7. Completion Criteria

| # | Criteria | FR |
|---|----------|----|
| 1 | 드로어 내 상세/태스크/코멘트/히스토리 4개 탭 표시 | FR-01 |
| 2 | 탭 클릭 시 해당 패널만 표시 (JS, 서버 요청 없음) | FR-01 |
| 3 | 기본 탭은 "상세" | FR-01 |
| 4 | 태스크/코멘트 탭에 카운트 배지 표시 | FR-01 |
| 5 | 드로어 헤더에 "다음 단계 →" 버튼 표시 | FR-02 |
| 6 | 다음 단계 버튼 클릭 → move_status PATCH 전송 | FR-02 |
| 7 | delivered 상태이면 다음 단계 버튼 숨김 | FR-02 |
| 8 | 우선순위 배지 클릭 → 드롭다운 표시 | FR-03 |
| 9 | 드롭다운 선택 → quick_update PATCH 전송 | FR-03 |
| 10 | 현재 우선순위에 체크 표시 | FR-03 |
| 11 | Gap Analysis Match Rate >= 90% | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial design | bkit:pdca |
