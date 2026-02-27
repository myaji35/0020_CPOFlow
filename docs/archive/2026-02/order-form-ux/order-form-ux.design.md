# order-form-ux Design

## 1. Overview

**Feature**: order-form-ux (주문 생성/수정 폼 UX 개선)
**Design Date**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/order-form-ux.plan.md`
**Implementation Target**:
- `app/views/orders/new.html.erb`
- `app/views/orders/_form.html.erb`

---

## 2. Current State Analysis

### 2.1 new.html.erb (현재, 14줄)
- `max-w-3xl mx-auto` 전체 페이지 레이아웃
- card 안에 `_form` partial 렌더링

### 2.2 _form.html.erb (현재, 163줄)
- autocomplete Stimulus controller (client/supplier/project) 적용됨
- `customer_name` 필드 **누락** (모델 validation `presence: true` 있음)
- 섹션 구분 없이 필드 나열

### 2.3 Key Facts (실측)

- `Order.new` → `due_date = 30.days.from_now` (controller new 액션)
- `order_params` `:customer_name` 허용됨
- `projects#search` — `client_id` 파라미터 **미지원** (현재 `q`만 받음)
- autocomplete controller values: `url`, `placeholder`, `sublabel` (filterParam 없음)
- 생성 후 `redirect_to kanban_path` (기존 동작 유지)

---

## 3. Functional Requirements Design

### FR-01: 슬라이드오버 레이아웃 (new.html.erb)

#### 3.1 new.html.erb 전환

```erb
<%# new.html.erb — 슬라이드오버 래퍼로 교체 %>
<div class="fixed inset-0 bg-black/40 z-40" onclick="history.back()"></div>

<div class="fixed top-0 right-0 h-full w-full max-w-xl bg-white dark:bg-gray-800
            shadow-2xl z-50 flex flex-col overflow-hidden
            transform transition-transform duration-300 ease-in-out">
  <%# 헤더 %>
  <div class="flex items-center gap-3 px-6 py-4 border-b border-gray-100 dark:border-gray-700 flex-shrink-0">
    <h2 class="flex-1 text-base font-semibold text-gray-900 dark:text-white">새 주문 등록</h2>
    <%= link_to kanban_path,
          class: "p-1.5 rounded-lg text-gray-400 hover:text-gray-600 dark:hover:text-gray-300
                  hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors" do %>
      <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    <% end %>
  </div>
  <%# 바디 (스크롤) %>
  <div class="flex-1 overflow-y-auto p-6">
    <%= render "form", order: @order %>
  </div>
</div>
```

**ESC 키 닫기** — 인라인 script:
```javascript
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') history.back();
});
```

---

### FR-02: _form.html.erb — 섹션 그룹핑 + customer_name 추가

#### 3.2 섹션 구조 (4개)

```
[섹션 1 — 기본 정보]
  - title (full width)
  - customer_name  |  발주처(client autocomplete)

[섹션 2 — 거래 정보]
  - 공급사(supplier autocomplete)  |  현장/프로젝트(project autocomplete)
  - 납기일 date input  +  [1주][2주][1개월] 퀵픽 버튼

[섹션 3 — 품목 / 금액]
  - 품목명  |  수량  |  예상금액(USD)

[섹션 4 — 추가 정보]
  - 우선순위  |  태그
  - 설명 (textarea)

[액션 버튼]
  - [Create Order]  [Cancel]
```

#### 3.3 섹션 헤더 패턴

```erb
<div class="space-y-6">
  <%# === 섹션 1: 기본 정보 === %>
  <div>
    <h3 class="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase tracking-wider mb-3">
      기본 정보
    </h3>
    <div class="space-y-3">
      <%# 필드들 %>
    </div>
  </div>
  <div class="border-t border-gray-100 dark:border-gray-700"></div>
  <%# 다음 섹션... %>
</div>
```

#### 3.4 customer_name 필드 추가

```erb
<div>
  <%= f.label :customer_name, "고객사명", class: "block text-sm font-medium ..." %>
  <%= f.text_field :customer_name, placeholder: "e.g. KEPCO Engineering",
      class: "w-full px-3 py-2 border ... rounded-lg text-sm ..." %>
</div>
```

섹션 1에서 `title` 아래, `client_id` 와 나란히 2-col grid에 배치.

---

### FR-03: 납기일 퀵픽 버튼

#### 3.5 HTML

```erb
<div>
  <%= f.label :due_date, "납기일", class: "block text-sm font-medium ..." %>
  <div class="flex items-center gap-2">
    <%= f.date_field :due_date,
        class: "flex-1 px-3 py-2 border ... rounded-lg text-sm ..." %>
    <button type="button" onclick="setDueDateOffset(7)"
            class="px-2.5 py-2 text-xs font-medium border border-gray-300 dark:border-gray-600
                   text-gray-600 dark:text-gray-400 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700
                   transition-colors whitespace-nowrap">1주</button>
    <button type="button" onclick="setDueDateOffset(14)"
            class="px-2.5 py-2 text-xs font-medium border border-gray-300 dark:border-gray-600
                   text-gray-600 dark:text-gray-400 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700
                   transition-colors whitespace-nowrap">2주</button>
    <button type="button" onclick="setDueDateOffset(30)"
            class="px-2.5 py-2 text-xs font-medium border border-gray-300 dark:border-gray-600
                   text-gray-600 dark:text-gray-400 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700
                   transition-colors whitespace-nowrap">1개월</button>
  </div>
</div>
```

#### 3.6 setDueDateOffset() JavaScript

```javascript
function setDueDateOffset(days) {
  var d = new Date();
  d.setDate(d.getDate() + days);
  var yyyy = d.getFullYear();
  var mm   = String(d.getMonth() + 1).padStart(2, '0');
  var dd   = String(d.getDate()).padStart(2, '0');
  var field = document.getElementById('order_due_date');
  if (field) field.value = yyyy + '-' + mm + '-' + dd;
}
```

`<script>` 블록은 `_form.html.erb` 하단에 인라인 추가.

---

### FR-04: 발주처↔프로젝트 연동 필터링

#### 3.7 projects#search client_id 지원 추가

`app/controllers/projects_controller.rb` search 액션 수정:

```ruby
def search
  q = params[:q].to_s.strip
  projects = Project.includes(:client).active.by_name
  projects = projects.where("projects.name LIKE ?", "%#{q}%") if q.present?
  projects = projects.where(client_id: params[:client_id]) if params[:client_id].present?
  results = projects.limit(10).map { |p|
    { id: p.id, name: p.name, client_name: p.client&.name, status: p.status }
  }
  render json: results
end
```

#### 3.8 client autocomplete → project 필터 연동 JS

client autocomplete 선택 시 project의 `data-autocomplete-url-value` 를 갱신:

```erb
<%# client autocomplete div에 id 추가 %>
<div data-controller="autocomplete"
     data-autocomplete-url-value="<%= search_clients_path %>"
     ...
     id="client-autocomplete-<%= order.id.to_s.presence || 'new' %>"
     data-onselect="updateProjectFilter">
```

```javascript
// client 선택 완료 시 project URL 갱신
function updateProjectFilter(clientId) {
  var projectAc = document.getElementById('project-autocomplete');
  if (!projectAc) return;
  var baseUrl = projectAc.dataset.autocompleteUrlValue.split('?')[0];
  projectAc.dataset.autocompleteUrlValue = clientId
    ? baseUrl + '?client_id=' + clientId
    : baseUrl;
}
```

**구현 방식**: autocomplete controller의 `select()` 메서드에서 `data-onselect` 콜백을 호출하는 대신, **simpler approach** — client hidden field 변경 감지:

```javascript
// _form.html.erb 하단 인라인 JS
document.addEventListener('change', function(e) {
  if (e.target.id === 'order_client_id') {
    var projectEl = document.getElementById('project-autocomplete');
    if (!projectEl) return;
    var base = '<%= search_projects_path %>';
    projectEl.dataset.autocompleteUrlValue =
      e.target.value ? base + '?client_id=' + e.target.value : base;
    // 기존 project 선택 초기화
    var projectHidden = projectEl.querySelector('[data-autocomplete-target="hidden"]');
    if (projectHidden) projectHidden.dispatchEvent(new Event('clear-from-parent'));
  }
});
```

`project-autocomplete` id를 project autocomplete div에 추가.

---

## 4. Implementation Order

```
Step 1: app/controllers/projects_controller.rb
  - search 액션에 client_id 필터 추가 (1줄)

Step 2: app/views/orders/_form.html.erb
  - 섹션 그룹핑 재구성 (FR-05)
  - customer_name 필드 추가 (FR-04)
  - 납기일 퀵픽 버튼 추가 (FR-03)
  - 발주처↔프로젝트 연동 JS (FR-04)
  - setDueDateOffset() + 연동 JS 인라인 추가

Step 3: app/views/orders/new.html.erb
  - 슬라이드오버 레이아웃으로 교체 (FR-01)
```

---

## 5. File Summary

| File | Lines (현재) | 변경 내용 |
|------|:---:|-------|
| `app/controllers/projects_controller.rb` | — | search에 client_id 필터 (+1줄) |
| `app/views/orders/_form.html.erb` | 163 | 섹션 재구성 + customer_name + 퀵픽 + 연동 JS (~+30줄) |
| `app/views/orders/new.html.erb` | 14 | 슬라이드오버 레이아웃으로 전면 교체 |

---

## 6. Completion Criteria

| # | Criteria | FR |
|---|----------|----|
| 1 | new.html.erb 슬라이드오버 레이아웃 (우측 패널) | FR-01 |
| 2 | ESC / 배경 클릭 시 칸반으로 돌아감 | FR-01 |
| 3 | customer_name 필드 폼에 존재 | FR-04 |
| 4 | "1주 / 2주 / 1개월" 버튼 클릭 시 납기일 자동 설정 | FR-03 |
| 5 | 발주처 선택 시 프로젝트 검색에 client_id 필터 적용 | FR-02 |
| 6 | 폼을 4개 섹션(기본/거래/품목/추가)으로 시각 구분 | FR-05 |
| 7 | 폼 제출 후 칸반 페이지로 리다이렉트 | — |
| 8 | Gap Analysis Match Rate >= 90% | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial design | bkit:pdca |
