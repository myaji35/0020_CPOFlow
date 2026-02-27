# Feature Design: ux-enhancement

**Feature Name**: 실무 UX 편의 기능 강화
**Based On**: `docs/01-plan/features/ux-enhancement.plan.md`
**Created**: 2026-02-28
**Phase**: Design

---

## AS-IS 코드 실측 결과 (Plan 대비 Gap 재조정)

### FR-01: 칸반 드래그 — 이미 완전 구현됨 ✅ → 범위 제거

| 항목 | 실측 결과 |
|------|----------|
| `kanban/index.html.erb` | SortableJS CDN 로드, `group: 'kanban'` 드래그앤드롭 완비 |
| `kanban_controller.rb#move` | `render json: { success: true }` 낙관적 UI |
| JS `onEnd` | fetch PATCH, 실패 시 원위치 복원, 토스트 알림 |

**→ FR-01은 이미 완성. 이번 사이클에서 제외.**

### FR-02: 일괄 처리 액션바 — 상태변경 UI 있음, 담당자 배정 없음 ⚠️

| 항목 | 실측 결과 |
|------|----------|
| `bulk_select_controller.js` | 체크박스 선택·form submit·CSV 완비 |
| `orders/index.html.erb` L181–212 | 액션바: 상태변경 select + 적용 버튼 ✅ |
| 담당자 배정 UI | **없음** — `BulkController#update`의 `when "assign"` 핸들러는 있으나 뷰에 UI 없음 ❌ |
| `bulk_select_controller.js` `bulkAction` | `dataset.action_type` 읽어서 form submit — `statusSelect` 연결 불완전 |

**→ FR-02 실제 Gap: ① 담당자 배정 드롭다운 UI 추가 ② `bulkAction`에서 statusSelect 값 자동 반영**

### FR-03: 납기일 범위 필터 — 미구현 ❌

| 항목 | 실측 결과 |
|------|----------|
| `orders_controller.rb:27-28` | `date_from/date_to` → **`created_at` 기준** 필터만 존재 |
| `due_from/due_to` | **없음** — due_date 기준 필터 없음 |
| 뷰 필터 폼 | due_date 범위 입력 필드 없음 |

**→ FR-03: 컨트롤러 + 뷰 모두 추가 필요**

### FR-04: 인라인 빠른 수정 — 미구현 ❌

| 항목 | 실측 결과 |
|------|----------|
| 납기일 셀 L142-150 | 읽기 전용 표시 (`strftime`) — 수정 불가 |
| 상태 셀 L113-126 | 뱃지 표시만 — 수정 불가 |
| `inline_edit_controller.js` | **없음** |
| `OrdersController#quick_update` | **없음** |

**→ FR-04: Stimulus 컨트롤러 + 백엔드 액션 신규 구현 필요**

---

## Gap별 구현 설계

### FR-02: 일괄 처리 액션바 완성

**파일 1: `app/views/orders/index.html.erb`**

액션바 (L182–212) 에서 상태변경 `<select>` 아래에 담당자 배정 드롭다운 추가:

```erb
<%# 담당자 배정 — 기존 상태변경 select 아래에 삽입 %>
<div class="h-4 w-px bg-white/20"></div>
<select data-bulk-select-target="assignSelect"
        class="text-xs bg-white/10 border border-white/20 rounded-lg px-2 py-1 text-white focus:outline-none focus:ring-1 focus:ring-white/40">
  <option value="">담당자 배정...</option>
  <% User.order(:name).each do |u| %>
    <option value="<%= u.id %>"><%= u.display_name %></option>
  <% end %>
</select>
<button data-action="click->bulk-select#bulkAssign"
        class="text-xs bg-green-500 hover:bg-green-400 px-3 py-1.5 rounded-lg transition-colors font-medium">
  배정
</button>
```

**파일 2: `app/javascript/controllers/bulk_select_controller.js`**

① `static targets`에 `"assignSelect"` 추가
② `bulkAction` 메서드 수정 — `statusSelect` 값을 form hidden input으로 자동 전달
③ `bulkAssign` 메서드 신규 추가

```js
// targets 추가
static targets = ["checkbox", "selectAll", "actionBar", "count", "form", "statusSelect", "assignSelect"]

// bulkAction 수정: statusSelect 값을 자동으로 params에 포함
bulkAction(e) {
  const ids = this.selectedIds()
  if (ids.length === 0) return
  const status = this.hasStatusSelectTarget ? this.statusSelectTarget.value : ""
  if (!status) { alert("상태를 선택해주세요."); return }

  const form = this.formTarget
  // 기존 hidden inputs 제거 후 재주입
  form.querySelectorAll('input[name="order_ids[]"], input[name="action_type"], input[name="status"]').forEach(el => el.remove())
  ids.forEach(id => {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = "order_ids[]"; i.value = id
    form.appendChild(i)
  })
  ;[["action_type", "status"], ["status", status]].forEach(([name, val]) => {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = name; i.value = val
    form.appendChild(i)
  })
  form.submit()
}

// bulkAssign 신규
bulkAssign() {
  const ids = this.selectedIds()
  if (ids.length === 0) return
  const userId = this.hasAssignSelectTarget ? this.assignSelectTarget.value : ""
  if (!userId) { alert("담당자를 선택해주세요."); return }

  const form = this.formTarget
  form.querySelectorAll('input[name="order_ids[]"], input[name="action_type"], input[name="user_id"]').forEach(el => el.remove())
  ids.forEach(id => {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = "order_ids[]"; i.value = id
    form.appendChild(i)
  })
  ;[["action_type", "assign"], ["user_id", userId]].forEach(([name, val]) => {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = name; i.value = val
    form.appendChild(i)
  })
  form.submit()
}

// clearAll 신규 (취소 버튼용)
clearAll() {
  this.checkboxTargets.forEach(cb => cb.checked = false)
  if (this.hasSelectAllTarget) this.selectAllTarget.checked = false
  this.updateState()
}
```

---

### FR-03: 납기일 범위 필터 추가

**파일 1: `app/controllers/orders_controller.rb`**

index 액션 기간 필터 블록 (L18–29) 아래에 추가:

```ruby
# 납기일 범위 필터
@orders = @orders.where(due_date: params[:due_from]..) if params[:due_from].present?
@orders = @orders.where(due_date: ..params[:due_to])   if params[:due_to].present?
```

필터 초기화 조건 (뷰 L53)에 `due_from`, `due_to` 추가:
```ruby
[ :q, :status, :period, :client_id, :supplier_id, :project_id, :user_id, :due_from, :due_to ]
```

**파일 2: `app/views/orders/index.html.erb`**

2행 필터 (`<div class="flex flex-wrap items-center gap-2">`) 내 검색 버튼 앞에 삽입:

```erb
<%# 납기일 범위 %>
<div class="flex items-center gap-1">
  <span class="text-xs text-gray-400 dark:text-gray-500 whitespace-nowrap">납기</span>
  <%= f.date_field :due_from, value: params[:due_from],
      class: "text-xs border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30 w-32" %>
  <span class="text-xs text-gray-300 dark:text-gray-600">~</span>
  <%= f.date_field :due_to, value: params[:due_to],
      class: "text-xs border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30 w-32" %>
</div>
```

---

### FR-04: 오더 목록 인라인 빠른 수정

**파일 1: `app/javascript/controllers/inline_edit_controller.js` (신규)**

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  saveDueDate(e) {
    this.#patch({ due_date: e.target.value })
  }

  saveStatus(e) {
    this.#patch({ status: e.target.value })
  }

  #patch(body) {
    const csrf = document.querySelector('meta[name="csrf-token"]').content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ order: body })
    })
    .then(r => r.json())
    .then(data => {
      if (!data.success) {
        alert("저장 실패: " + (data.errors || []).join(", "))
        location.reload()
      }
    })
    .catch(() => { alert("네트워크 오류"); location.reload() })
  }
}
```

**파일 2: `app/controllers/orders_controller.rb`**

`quick_update` 액션 추가 (`move_status` 아래):

```ruby
def quick_update
  permitted = params.require(:order).permit(:due_date, :status)
  if @order.update(permitted)
    Activity.create!(order: @order, user: current_user, action: "updated")
    render json: { success: true }
  else
    render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
  end
end
```

`before_action :set_order`에 `quick_update` 추가:
```ruby
before_action :set_order, only: %i[show edit update destroy move_status quick_update]
```

라우트 (`config/routes.rb`) — orders resources 멤버에 추가:
```ruby
resources :orders do
  member do
    patch :move_status
    patch :quick_update   # 추가
  end
  ...
end
```

**파일 3: `app/views/orders/index.html.erb`**

납기일 셀 (L142–150) 교체:
```erb
<td class="px-5 py-3"
    data-controller="inline-edit"
    data-inline-edit-url-value="<%= quick_update_order_path(order) %>">
  <input type="date"
         value="<%= order.due_date&.strftime('%Y-%m-%d') %>"
         data-action="change->inline-edit#saveDueDate"
         class="text-xs border-0 bg-transparent p-0 w-24 focus:ring-1 focus:ring-primary/30 rounded
                <%= order.due_date ? due_date_color_class(order.due_date) : 'text-gray-400' %>
                cursor-pointer">
</td>
```

상태 셀 (L113–126) 교체:
```erb
<td class="px-5 py-3"
    data-controller="inline-edit"
    data-inline-edit-url-value="<%= quick_update_order_path(order) %>">
  <select data-action="change->inline-edit#saveStatus"
          class="text-xs border-0 bg-transparent p-0 focus:ring-1 focus:ring-primary/30 rounded cursor-pointer
                 <%= case order.status
                     when 'inbox'      then 'text-gray-700 dark:text-gray-300'
                     when 'reviewing'  then 'text-blue-700 dark:text-blue-400'
                     when 'quoted'     then 'text-purple-700 dark:text-purple-400'
                     when 'confirmed'  then 'text-indigo-700 dark:text-indigo-400'
                     when 'procuring'  then 'text-yellow-700 dark:text-yellow-400'
                     when 'qa'         then 'text-orange-700 dark:text-orange-400'
                     when 'delivered'  then 'text-green-700 dark:text-green-400'
                     else 'text-gray-700 dark:text-gray-300'
                     end %>">
    <% Order::STATUS_LABELS.each do |k, v| %>
      <option value="<%= k %>" <%= 'selected' if order.status == k %>><%= v %></option>
    <% end %>
  </select>
</td>
```

---

## 구현 순서

| 순서 | 파일 | 변경 내용 | 난이도 |
|------|------|-----------|--------|
| 1 | `config/routes.rb` | `quick_update` 멤버 라우트 추가 | ⭐ |
| 2 | `app/controllers/orders_controller.rb` | `quick_update` 액션 + before_action + `due_from/due_to` 필터 | ⭐ |
| 3 | `app/javascript/controllers/inline_edit_controller.js` | 신규 Stimulus 컨트롤러 | ⭐⭐ |
| 4 | `app/javascript/controllers/bulk_select_controller.js` | targets 추가, bulkAction 수정, bulkAssign/clearAll 신규 | ⭐⭐ |
| 5 | `app/views/orders/index.html.erb` | 납기일 필터 + 담당자배정 UI + 인라인 수정 셀 교체 | ⭐⭐ |

**총 수정 파일: 5개 (신규 1개 포함) / 예상 추가 코드: ~120줄**

---

## 범위 재조정 (Plan 대비)

| FR | Plan | Design 재조정 |
|----|------|--------------|
| FR-01 | 칸반 Turbo Stream | **제외** — 이미 SortableJS+fetch JSON으로 완전 구현됨 |
| FR-02 | 일괄처리 액션바 | **축소** — 상태변경 UI 있음, 담당자배정 UI + bulkAction 수정만 필요 |
| FR-03 | 납기일 범위 필터 | **유지** — 컨트롤러 + 뷰 추가 |
| FR-04 | 인라인 빠른 수정 | **유지** — inline_edit_controller.js + quick_update 액션 신규 |

---

## 의존성 & 사전 확인

| 항목 | 상태 |
|------|:----:|
| `due_date_color_class` 헬퍼 | ✅ ApplicationHelper에 구현됨 |
| `Orders::BulkController#update` assign 핸들러 | ✅ 구현됨 |
| `Order::STATUS_LABELS` | ✅ |
| `quick_update_order_path` 라우트 | ❌ 추가 필요 |
| `inline_edit_controller.js` importmap 등록 | ✅ pin 없이 자동 (`controllers/` 디렉토리 자동 로드) |
