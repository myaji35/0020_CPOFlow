# search-ux Plan

## 1. Feature Overview

**Feature Name**: search-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (2~3 files)

### 1.1 Summary

커맨드 팔레트 검색 UX 개선 — 현재 기능하는 Cmd+K 검색에 최근 검색어, Order 결과 드로어 연동, 검색 결과 하이라이팅을 추가한다.

### 1.2 Current State (실측)

**`command_palette_controller.js`** (143줄):
- Cmd+K / Ctrl+K 단축키로 열기
- 280ms 디바운스 후 `/search?q=` API 호출
- `↑↓` 키보드 내비게이션 + `Enter` 이동
- `renderResults()`: 타입 배지 + label + sub + 화살표 아이콘
- 결과 클릭 시: `window.location.href = item.url` (전체 페이지 이동)

**`search_controller.rb`** (42줄):
- Order (title/customer_name LIKE), Client, Supplier, Employee, Project 5가지 타입
- JSON 반환: `{ type, icon, label, sub, url }`

**`layouts/application.html.erb`** (L86-119):
- 커맨드 팔레트 HTML (모달 + 입력 + 결과 영역)
- 푸터: `↑↓ / ↵ / ⌘K` 힌트

### 1.3 Problem Statement

1. **최근 검색어 없음**: 팔레트 열면 빈 힌트만 표시 — 재검색 불편
2. **Order 결과 클릭 → 전체 페이지 이동**: `openOrderDrawer()` 미연동
3. **검색어 하이라이팅 없음**: 결과에서 매칭 텍스트 시각 강조 없음
4. **헤더 검색 버튼 동작 불안정**: `_controller?.open()` 패턴이 Stimulus 내부 접근으로 불안정

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **최근 검색어**: 팔레트 열 때 최근 5개 표시, 클릭 시 바로 검색 |
| FR-02 | **Order 드로어 연동**: Order 타입 결과 클릭 → `openOrderDrawer()` |
| FR-03 | **검색어 하이라이팅**: 결과 label에서 q 매칭 부분 `<mark>` 강조 |
| FR-04 | **헤더 버튼 안정화**: `data-action` 이벤트로 Stimulus open() 호출 |

### Out of Scope
- 검색 결과 페이지 (`/search` 전체 페이지)
- 서버사이드 검색 로직 변경
- 검색 필터 (타입별 제한)

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/javascript/controllers/command_palette_controller.js` | FR-01, FR-02, FR-03 |
| `app/views/layouts/application.html.erb` | FR-04 (헤더 버튼 + 최근 검색어 영역) |

### 3.2 최근 검색어 저장소

`localStorage` 사용 — key: `cpoflow_recent_searches`, value: JSON 배열 (최대 5개)

```javascript
// 저장
saveRecentSearch(q) {
  const recent = this.getRecentSearches()
  const updated = [q, ...recent.filter(r => r !== q)].slice(0, 5)
  localStorage.setItem('cpoflow_recent_searches', JSON.stringify(updated))
}

// 조회
getRecentSearches() {
  try { return JSON.parse(localStorage.getItem('cpoflow_recent_searches') || '[]') }
  catch { return [] }
}
```

### 3.3 Order 드로어 연동

`renderResults()`에서 `order` 타입은 `<a href>` 대신 `<div onclick>`:

```javascript
if (item.type === "order") {
  return `<div onclick="closeCommandPalette(); openOrderDrawer(${item.id}, ${JSON.stringify(item.label)}, '${item.url}')" ...>`
}
```

`search_controller.rb`에서 `id` 필드 추가 필요.

### 3.4 하이라이팅

```javascript
highlight(text, q) {
  const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return text.replace(new RegExp(`(${escaped})`, 'gi'),
    '<mark class="bg-yellow-100 dark:bg-yellow-900/40 text-inherit rounded px-0.5">$1</mark>')
}
```

### 3.5 헤더 버튼 안정화

현재 (불안정):
```erb
onclick="document.querySelector('[data-controller=command-palette] ...')?.open()"
```

변경 (안정):
```erb
onclick="document.dispatchEvent(new CustomEvent('command-palette:open'))"
```

컨트롤러에서:
```javascript
connect() {
  document.addEventListener('command-palette:open', () => this.open())
}
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 팔레트 열면 최근 검색어 최대 5개 표시 |
| 2 | 검색 후 Enter/클릭 시 해당 검색어 localStorage 저장 |
| 3 | Order 결과 클릭 → openOrderDrawer() 실행 (페이지 이동 없음) |
| 4 | 결과 label에서 검색어 하이라이팅 표시 |
| 5 | 헤더 검색 버튼 클릭 → 팔레트 안정적으로 열림 |
| 6 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `openOrderDrawer()` 함수 (layouts/application.html.erb) — 기존 존재
- `search_controller.rb` — `id` 필드 추가 필요 (Order 타입)
- `localStorage` — 브라우저 내장

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
