# search-ux Design

## 1. Overview

**Feature**: search-ux (검색 UX 개선)
**Design Date**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/search-ux.plan.md`
**Implementation Target**:
- `app/javascript/controllers/command_palette_controller.js`
- `app/views/layouts/application.html.erb`
- `app/controllers/search_controller.rb`

---

## 2. Current State Analysis

### 2.1 command_palette_controller.js (현재)

```javascript
// 문제 1: Order 결과도 일반 링크로 처리 (전체 페이지 이동)
this.resultsTarget.innerHTML = items.map((item, i) => `
  <a href="${item.url}" ...>${item.label}</a>
`).join("")

// 문제 2: 하이라이팅 없음
<span class="block text-sm ...">${item.label}</span>

// 문제 3: 팔레트 열면 emptyHint()만 표시 (최근 검색어 없음)
open() {
  this.resultsTarget.innerHTML = this.emptyHint()
}
```

### 2.2 layouts/application.html.erb (현재, L10-15)

```erb
<!-- 헤더 검색 버튼 — 불안정한 Stimulus 내부 접근 -->
<button onclick="document.querySelector('[data-controller=command-palette] ...')
                  ?.closest(...)?.classList.remove('hidden')
                  || document.querySelector('[data-controller=command-palette]')?._controller?.open()">
```

### 2.3 search_controller.rb (현재)

```ruby
# Order 결과에 id 필드 없음 → openOrderDrawer 연동 불가
{ type: "order", icon: "clipboard", label: o.title,
  sub: Order::STATUS_LABELS[o.status], url: order_path(o) }
```

---

## 3. Functional Requirements Design

### FR-01: 최근 검색어 표시

#### 3.1 open() 수정

```javascript
open() {
  this.modalTarget.classList.remove("hidden")
  this.inputTarget.value = ""
  this.inputTarget.focus()
  this.isOpen = true
  this.selectedIndex = -1
  this.showRecentSearches()   // ← emptyHint() 대신
}
```

#### 3.2 showRecentSearches()

```javascript
showRecentSearches() {
  const recent = this.getRecentSearches()
  if (recent.length === 0) {
    this.resultsTarget.innerHTML = this.emptyHint()
    return
  }
  this.resultsTarget.innerHTML = `
    <div class="px-4 pt-3 pb-1">
      <p class="text-xs font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wide">최근 검색</p>
    </div>
    ${recent.map(q => `
      <div onclick="this.closest('[data-controller=command-palette]')
                        .__stimulusController.searchFrom('${q.replace(/'/g, "\\'")}')"
           class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors result-item recent-item">
        <svg class="w-4 h-4 text-gray-300 dark:text-gray-600 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/>
        </svg>
        <span class="flex-1 text-sm text-gray-600 dark:text-gray-300">${q}</span>
        <svg class="w-3.5 h-3.5 text-gray-200 dark:text-gray-600 group-hover:text-gray-400 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="9 18 15 12 9 6"/>
        </svg>
      </div>
    `).join("")}
  `
}
```

#### 3.3 searchFrom(q) — 최근 검색어 클릭 시

```javascript
searchFrom(q) {
  this.inputTarget.value = q
  this.fetchResults(q)
}
```

#### 3.4 localStorage 헬퍼

```javascript
saveRecentSearch(q) {
  const recent = this.getRecentSearches()
  const updated = [q, ...recent.filter(r => r !== q)].slice(0, 5)
  localStorage.setItem('cpoflow_recent_searches', JSON.stringify(updated))
}

getRecentSearches() {
  try { return JSON.parse(localStorage.getItem('cpoflow_recent_searches') || '[]') }
  catch { return [] }
}
```

#### 3.5 저장 시점

검색 결과에서 항목 클릭 시 OR Enter로 이동 시:

```javascript
selectCurrent() {
  const items = this.resultsTarget.querySelectorAll(".result-item:not(.recent-item)")
  if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
    const q = this.inputTarget.value.trim()
    if (q.length >= 2) this.saveRecentSearch(q)
    // 이동 처리 (FR-02에서 분기)
    this.activateItem(items[this.selectedIndex])
  }
}
```

---

### FR-02: Order 드로어 연동

#### 3.6 search_controller.rb — id 필드 추가

```ruby
# Order 결과에 id 추가
results += Order.where("title LIKE ? OR customer_name LIKE ?", "%#{q}%", "%#{q}%")
                .limit(5).map do |o|
                  { type: "order", id: o.id, icon: "clipboard", label: o.title,
                    sub: Order::STATUS_LABELS[o.status], url: order_path(o) }
                end
```

#### 3.7 renderResults() — Order 타입 분기

```javascript
renderResults(items, q) {
  // ...
  this.resultsTarget.innerHTML = items.map((item, i) => {
    const label = this.highlight(item.label, q)
    const sub   = item.sub ? this.highlight(item.sub, q) : ""

    if (item.type === "order") {
      // Order → openOrderDrawer (페이지 이동 없음)
      return `
        <div data-result-item
             data-order-id="${item.id}"
             data-order-title="${item.label.replace(/"/g, '&quot;')}"
             data-order-url="${item.url}"
             class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors result-item"
             data-index="${i}">
          <span class="inline-flex ... ${typeColor[item.type]}">주문</span>
          <span class="flex-1 min-w-0">
            <span class="block text-sm text-gray-900 dark:text-white truncate">${label}</span>
            ${sub ? `<span class="block text-xs text-gray-400 truncate">${sub}</span>` : ""}
          </span>
          <svg class="w-4 h-4 text-gray-300 group-hover:text-gray-500 flex-shrink-0" ...chevron...></svg>
        </div>`
    } else {
      // 기타 → 기존 <a href> 링크
      return `
        <a href="${item.url}" data-result-item class="... result-item" data-index="${i}">
          ...
        </a>`
    }
  }).join("")
}
```

#### 3.8 activateItem() — 클릭/Enter 공통 처리

```javascript
activateItem(el) {
  if (el.dataset.orderId) {
    // Order 드로어
    const q = this.inputTarget.value.trim()
    if (q.length >= 2) this.saveRecentSearch(q)
    this.close()
    openOrderDrawer(
      el.dataset.orderId,
      el.dataset.orderTitle,
      el.dataset.orderUrl
    )
  } else if (el.href) {
    // 일반 링크
    const q = this.inputTarget.value.trim()
    if (q.length >= 2) this.saveRecentSearch(q)
    window.location.href = el.href
  }
}
```

결과 클릭 이벤트도 activateItem() 위임:

```javascript
// resultsTarget에 이벤트 위임
this.resultsTarget.addEventListener('click', (e) => {
  const item = e.target.closest('.result-item:not(.recent-item)')
  if (item) this.activateItem(item)
})
```

---

### FR-03: 검색어 하이라이팅

#### 3.9 highlight() 메서드

```javascript
highlight(text, q) {
  if (!q || !text) return text
  const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return String(text).replace(
    new RegExp(`(${escaped})`, 'gi'),
    '<mark class="bg-yellow-100 dark:bg-yellow-900/40 text-inherit not-italic rounded px-0.5">$1</mark>'
  )
}
```

`label`과 `sub` 양쪽 모두 `highlight()` 적용.

---

### FR-04: 헤더 버튼 안정화

#### 3.10 layouts/application.html.erb — 헤더 버튼

```erb
<!-- Before (L10-15, 불안정) -->
<button onclick="document.querySelector(...)?.classList.remove('hidden') || ...?._controller?.open()">

<!-- After (CustomEvent 방식) -->
<button onclick="document.dispatchEvent(new CustomEvent('open-command-palette'))" ...>
```

#### 3.11 command_palette_controller.js — connect()

```javascript
connect() {
  this.handleKeydown = this.handleKeydown.bind(this)
  this.handleOpen    = () => this.open()              // ← 추가
  document.addEventListener("keydown", this.handleKeydown)
  document.addEventListener("open-command-palette", this.handleOpen)  // ← 추가
  this.selectedIndex = -1
  this.debounceTimer = null
}

disconnect() {
  document.removeEventListener("keydown", this.handleKeydown)
  document.removeEventListener("open-command-palette", this.handleOpen)  // ← 추가
}
```

---

## 4. Implementation Order

```
Step 1: search_controller.rb
  - Order 결과에 id 필드 추가 (1줄)

Step 2: command_palette_controller.js (전체 재작성)
  - connect/disconnect: CustomEvent 리스너 추가 (FR-04)
  - open(): showRecentSearches() 호출 (FR-01)
  - showRecentSearches(): 최근 검색어 HTML 렌더링 (FR-01)
  - searchFrom(q): 최근 검색어 클릭 처리 (FR-01)
  - getRecentSearches() / saveRecentSearch(q): localStorage (FR-01)
  - renderResults(): Order 타입 분기 + highlight() 적용 (FR-02, FR-03)
  - activateItem(el): 클릭/Enter 공통 처리 (FR-02)
  - selectCurrent(): activateItem() 위임 (FR-02)
  - highlight(text, q): 하이라이팅 (FR-03)
  - resultsTarget 이벤트 위임 등록 (FR-02)

Step 3: layouts/application.html.erb
  - 헤더 버튼 onclick → CustomEvent (FR-04)
```

---

## 5. File Summary

| File | Lines (현재) | 변경 내용 |
|------|:---:|-------|
| `app/controllers/search_controller.rb` | 42 | L12: `id: o.id` 추가 (+1줄) |
| `app/javascript/controllers/command_palette_controller.js` | 143 | 전면 재작성 (~190줄) |
| `app/views/layouts/application.html.erb` | ~200 | L10-15 헤더 버튼 onclick 교체 |

---

## 6. Completion Criteria

| # | Criteria | FR |
|---|----------|----|
| 1 | 팔레트 열면 최근 검색어 최대 5개 표시 | FR-01 |
| 2 | 최근 검색어 클릭 → 해당 검색어로 즉시 검색 | FR-01 |
| 3 | 검색 결과 클릭/Enter 시 검색어 localStorage 저장 | FR-01 |
| 4 | Order 결과 클릭 → openOrderDrawer() (페이지 이동 없음) | FR-02 |
| 5 | Order 외 결과 클릭 → 기존 페이지 이동 유지 | FR-02 |
| 6 | 검색 결과 label/sub에 검색어 하이라이팅 표시 | FR-03 |
| 7 | 헤더 검색 버튼 클릭 → 팔레트 안정적으로 열림 | FR-04 |
| 8 | Gap Analysis Match Rate >= 90% | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial design | bkit:pdca |
