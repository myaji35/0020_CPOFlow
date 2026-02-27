# Design: kanban-ux

## 개요

칸반 보드 UX 개선 — 상단 필터 바(FR-01) + 카드 퀵액션(FR-02)

- **Plan**: `docs/01-plan/features/kanban-ux.plan.md`
- **작성일**: 2026-02-28

---

## 실측 확인 사항

| 항목 | 값 |
|------|-----|
| KANBAN_COLUMNS | `%w[inbox reviewing quoted confirmed procuring qa delivered]` (7단계) |
| priority enum | `low(0) / medium(1) / high(2) / urgent(3)` |
| due_badge | `days < 0` → OVERDUE, `≤7` → D-N 빨강, `≤14` → D-N 주황, `>14` → 초록 |
| priority_badge | helper 함수, `order.priority` string |
| 드래그 핸들 | `.drag-handle` selector, `handle` 옵션 적용 |
| 카드 클릭 | `onclick="openOrderDrawer(id, title, path)"` inline |
| 기존 move API | `PATCH /orders/:id/move` → `{ status: newStatus }` |

---

## 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `app/views/kanban/index.html.erb` | 수정 | FR-01 필터 바 UI + 필터 JS + render locals 추가 |
| `app/views/kanban/_card.html.erb` | 수정 | FR-02 퀵액션 버튼 + data 속성 + relative 포지셔닝 |

컨트롤러 변경 없음.

---

## FR-01: 필터 바 설계

### 삽입 위치
`kanban/index.html.erb` — 기존 헤더 `</div>` (L16) 직후, `<!-- Kanban Board -->` 위

### 필터 바 레이아웃

```
┌──────────────────────────────────────────────────────────────────┐
│ [전체 ▼ 담당자] [전체|긴급|높음|보통 priority] [전체|D-7|지연 납기] [🔍 검색...] [✕ 초기화] │
└──────────────────────────────────────────────────────────────────┘
```

### ERB 구조

```erb
<!-- 필터 바 (FR-01) -->
<div id="kanban-filter-bar" class="flex flex-wrap items-center gap-2 mb-4 p-3 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">

  <%# 담당자 드롭다운 %>
  <select id="filter-assignee"
          class="text-xs border border-gray-200 dark:border-gray-600 rounded-lg px-2 py-1.5 bg-white dark:bg-gray-700 text-gray-700 dark:text-gray-200 focus:outline-none focus:ring-2 focus:ring-accent/40">
    <option value="">전체 담당자</option>
    <option value="me" data-user-id="<%= current_user.id %>">내 발주</option>
    <% User.order(:name).each do |u| %>
      <option value="<%= u.id %>"><%= u.display_name %></option>
    <% end %>
  </select>

  <%# 우선순위 토글 %>
  <div class="flex rounded-lg border border-gray-200 dark:border-gray-600 overflow-hidden text-xs">
    <% [["", "전체"], ["urgent", "긴급"], ["high", "높음"], ["medium", "보통"]].each do |val, lbl| %>
      <button class="filter-priority-btn px-2.5 py-1.5 bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors border-r border-gray-200 dark:border-gray-600 last:border-0"
              data-value="<%= val %>">
        <%= lbl %>
      </button>
    <% end %>
  </div>

  <%# 납기 토글 %>
  <div class="flex rounded-lg border border-gray-200 dark:border-gray-600 overflow-hidden text-xs">
    <% [["", "전체"], ["urgent", "D-7"], ["overdue", "지연"]].each do |val, lbl| %>
      <button class="filter-due-btn px-2.5 py-1.5 bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors border-r border-gray-200 dark:border-gray-600 last:border-0"
              data-value="<%= val %>">
        <%= lbl %>
      </button>
    <% end %>
  </div>

  <%# 키워드 검색 %>
  <div class="flex items-center gap-1.5 flex-1 min-w-[140px] max-w-[220px] border border-gray-200 dark:border-gray-600 rounded-lg px-2.5 py-1.5 bg-white dark:bg-gray-700">
    <svg class="w-3.5 h-3.5 text-gray-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
    <input id="filter-keyword" type="text" placeholder="검색..."
           class="text-xs bg-transparent text-gray-700 dark:text-gray-200 focus:outline-none w-full placeholder-gray-400 dark:placeholder-gray-500">
  </div>

  <%# 초기화 버튼 %>
  <button id="filter-reset"
          class="text-xs text-gray-400 dark:text-gray-500 hover:text-red-500 dark:hover:text-red-400 px-2 py-1.5 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors hidden">
    <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
  </button>
</div>
```

### 필터 JS 설계

기존 `<script>` 블록의 `DOMContentLoaded` 안에 추가:

```javascript
// ── FR-01: 필터 ──────────────────────────────────────────────
const filterAssignee = document.getElementById('filter-assignee');
const filterKeyword  = document.getElementById('filter-keyword');
const filterReset    = document.getElementById('filter-reset');
let   activePriority = '';
let   activeDue      = '';
const meId = '<%= current_user.id %>';

// 토글 버튼 활성화 스타일
function setActiveToggle(btnClass, activeVal) {
  document.querySelectorAll('.' + btnClass).forEach(function(btn) {
    const isActive = btn.dataset.value === activeVal;
    btn.classList.toggle('bg-accent',      isActive);
    btn.classList.toggle('text-white',     isActive);
    btn.classList.toggle('dark:bg-accent', isActive);
    btn.classList.toggle('bg-white',      !isActive);
    btn.classList.toggle('dark:bg-gray-700', !isActive);
    btn.classList.toggle('text-gray-600', !isActive);
    btn.classList.toggle('dark:text-gray-300', !isActive);
  });
}

// 카드 필터링
function applyFilters() {
  const assigneeVal = filterAssignee.value;
  const keyword     = filterKeyword.value.toLowerCase().trim();
  let   anyActive   = assigneeVal || activePriority || activeDue || keyword;

  document.querySelectorAll('[data-order-id]').forEach(function(card) {
    // 담당자 매칭
    const assigneeIds = (card.dataset.assigneeIds || '').split(',').filter(Boolean);
    const assigneeOk  = !assigneeVal ? true
      : assigneeVal === 'me' ? assigneeIds.includes(meId)
      : assigneeIds.includes(assigneeVal);

    // 우선순위 매칭
    const priorityOk = !activePriority || card.dataset.priority === activePriority;

    // 납기 매칭
    const dueDays = parseInt(card.dataset.dueDays, 10);
    const dueOk   = !activeDue ? true
      : activeDue === 'overdue' ? dueDays < 0
      : activeDue === 'urgent'  ? (dueDays >= 0 && dueDays <= 7)
      : true;

    // 키워드 매칭
    const text       = (card.dataset.title || '') + ' ' + (card.dataset.customer || '');
    const keywordOk  = !keyword || text.toLowerCase().includes(keyword);

    card.classList.toggle('hidden', !(assigneeOk && priorityOk && dueOk && keywordOk));
  });

  filterReset.classList.toggle('hidden', !anyActive);
  updateCounts();
}

// 우선순위 토글
document.querySelectorAll('.filter-priority-btn').forEach(function(btn) {
  btn.addEventListener('click', function() {
    activePriority = activePriority === btn.dataset.value ? '' : btn.dataset.value;
    setActiveToggle('filter-priority-btn', activePriority);
    applyFilters();
  });
});

// 납기 토글
document.querySelectorAll('.filter-due-btn').forEach(function(btn) {
  btn.addEventListener('click', function() {
    activeDue = activeDue === btn.dataset.value ? '' : btn.dataset.value;
    setActiveToggle('filter-due-btn', activeDue);
    applyFilters();
  });
});

// 담당자/키워드 이벤트
filterAssignee.addEventListener('change', applyFilters);
filterKeyword.addEventListener('input', applyFilters);

// 초기화
filterReset.addEventListener('click', function() {
  filterAssignee.value = '';
  filterKeyword.value  = '';
  activePriority = '';
  activeDue      = '';
  setActiveToggle('filter-priority-btn', '');
  setActiveToggle('filter-due-btn', '');
  applyFilters();
});

// 초기 상태 (전체 버튼 활성화)
setActiveToggle('filter-priority-btn', '');
setActiveToggle('filter-due-btn', '');
```

---

## FR-02: 퀵액션 버튼 설계

### `_card.html.erb` 변경

#### 1. render 호출 시 locals 전달 (index.html.erb)

기존:
```erb
<%= render "kanban/card", order: order %>
```

변경:
```erb
<% col_idx   = Order::KANBAN_COLUMNS.index(status) %>
<% prev_stat = col_idx > 0 ? Order::KANBAN_COLUMNS[col_idx - 1] : nil %>
<% next_stat = col_idx < Order::KANBAN_COLUMNS.length - 1 ? Order::KANBAN_COLUMNS[col_idx + 1] : nil %>
<%= render "kanban/card", order: order, prev_status: prev_stat, next_status: next_stat %>
```

#### 2. 카드 루트 div 변경

기존:
```erb
<div class="bg-white dark:bg-gray-800 rounded-lg border ... group"
     data-order-id="<%= order.id %>"
     title="클릭하여 상세 보기">
```

변경:
```erb
<div class="relative bg-white dark:bg-gray-800 rounded-lg border ... group"
     data-order-id="<%= order.id %>"
     data-priority="<%= order.priority %>"
     data-due-days="<%= order.days_until_due.to_i %>"
     data-assignee-ids="<%= order.assignees.map(&:id).join(',') %>"
     data-title="<%= order.title %>"
     data-customer="<%= order.customer_name %>"
     title="클릭하여 상세 보기">
```

#### 3. 퀵액션 버튼 삽입 (카드 루트 div 안, 헤더 위)

```erb
<%# 퀵액션 버튼 (FR-02) — hover 시 노출 %>
<div class="quick-actions absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity z-10">
  <% if local_assigns[:prev_status] %>
    <button class="quick-move-btn w-6 h-6 flex items-center justify-center rounded-md bg-white dark:bg-gray-700 border border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-600 shadow-sm transition-colors"
            data-order-id="<%= order.id %>"
            data-move-to="<%= local_assigns[:prev_status] %>"
            title="← <%= Order::STATUS_LABELS[local_assigns[:prev_status]] %>"
            onclick="event.stopPropagation()">
      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="15 18 9 12 15 6"/></svg>
    </button>
  <% end %>
  <% if local_assigns[:next_status] %>
    <button class="quick-move-btn w-6 h-6 flex items-center justify-center rounded-md bg-accent text-white hover:bg-blue-500 border border-accent shadow-sm transition-colors"
            data-order-id="<%= order.id %>"
            data-move-to="<%= local_assigns[:next_status] %>"
            title="→ <%= Order::STATUS_LABELS[local_assigns[:next_status]] %>"
            onclick="event.stopPropagation()">
      <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 18 15 12 9 6"/></svg>
    </button>
  <% end %>
</div>
```

#### 4. 퀵액션 JS (기존 script 블록에 추가)

```javascript
// ── FR-02: 퀵액션 ──────────────────────────────────────────
document.addEventListener('click', function(e) {
  const btn = e.target.closest('.quick-move-btn');
  if (!btn) return;
  e.stopPropagation();

  const orderId  = btn.dataset.orderId;
  const moveTo   = btn.dataset.moveTo;
  const cardEl   = document.querySelector('[data-order-id="' + orderId + '"]');
  const fromCol  = cardEl?.closest('.kanban-cards');

  if (!orderId || !moveTo || !cardEl) return;

  // 버튼 비활성화 (중복 클릭 방지)
  btn.disabled = true;
  btn.classList.add('opacity-50');

  fetch('/orders/' + orderId + '/move', {
    method:  'PATCH',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': CSRF },
    body:    JSON.stringify({ status: moveTo })
  })
  .then(function(r) { return r.json(); })
  .then(function(data) {
    if (data.success) {
      const targetCol = document.getElementById('column-' + moveTo);
      if (targetCol) {
        targetCol.insertBefore(cardEl, targetCol.firstChild);
        // data-due-days 등 카드 data 업데이트는 불필요 (이동만)
        updateCounts();
        const colLabel = targetCol.closest('.kanban-column')?.querySelector('.column-name')?.textContent || moveTo;
        showToast('→ ' + colLabel + ' 이동 완료', true);
      }
    } else {
      showToast('이동 실패: ' + (data.errors || []).join(', '), false);
    }
  })
  .catch(function() {
    showToast('네트워크 오류가 발생했습니다.', false);
  })
  .finally(function() {
    btn.disabled = false;
    btn.classList.remove('opacity-50');
  });
});
```

---

## 구현 순서

1. `kanban/_card.html.erb` — `relative` + data 속성 + 퀵액션 버튼 추가
2. `kanban/index.html.erb` — render locals 전달 + 필터 바 UI 추가
3. `kanban/index.html.erb` — 필터 JS + 퀵액션 JS를 기존 script 블록에 추가
4. rubocop 체크
5. `/pdca analyze kanban-ux`

---

## 완료 기준

- [ ] 담당자/우선순위/납기/키워드 필터 동작 (클라이언트 사이드)
- [ ] 필터 초기화 버튼 (활성 필터 있을 때만 표시)
- [ ] 카드 hover → 퀵액션 버튼 노출
- [ ] 퀵액션으로 다음/이전 단계 이동 + 토스트 확인
- [ ] 드래그 앤 드롭 기존 동작 유지
- [ ] `event.stopPropagation()` — 퀵액션 클릭이 드로어 열지 않음
- [ ] Gap Analysis Match Rate ≥ 90%
