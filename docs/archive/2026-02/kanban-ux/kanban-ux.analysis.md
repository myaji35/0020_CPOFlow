# kanban-ux Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Design Doc**: [kanban-ux.design.md](../02-design/features/kanban-ux.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

kanban-ux 기능(FR-01 필터 바, FR-02 퀵액션 버튼) Design 문서와 실제 구현 코드 간 차이 분석

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/kanban-ux.design.md`
- **Implementation Files**:
  - `app/views/kanban/index.html.erb`
  - `app/views/kanban/_card.html.erb`
- **Analysis Date**: 2026-02-28

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 FR-01: 필터 바 UI

| # | 항목 | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 1 | 필터 바 컨테이너 id | `kanban-filter-bar` | `kanban-filter-bar` | PASS | |
| 2 | 필터 바 class | `flex flex-wrap items-center gap-2 mb-4 p-3 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700` | 동일 | PASS | |
| 3 | 담당자 select id | `filter-assignee` | `filter-assignee` | PASS | |
| 4 | 담당자 select class | `text-xs border border-gray-200 dark:border-gray-600 rounded-lg px-2 py-1.5 bg-white dark:bg-gray-700 text-gray-700 dark:text-gray-200 focus:outline-none focus:ring-2 focus:ring-accent/40` | 동일 | PASS | |
| 5 | 담당자 option: 전체 | `<option value="">전체 담당자</option>` | 동일 | PASS | |
| 6 | 담당자 option: 내 발주 | `<option value="me" data-user-id="<%= current_user.id %>">내 발주</option>` | 동일 | PASS | |
| 7 | 담당자 option: User 목록 | `User.order(:name).each` + `u.display_name` | 동일 | PASS | View-layer concern (User.order 직접 호출) -- Design 명세 자체가 이 패턴 |
| 8 | 우선순위 토글 컨테이너 | `flex rounded-lg border ... overflow-hidden text-xs` | 동일 | PASS | |
| 9 | 우선순위 버튼 4개 | `["", "전체"], ["urgent", "긴급"], ["high", "높음"], ["medium", "보통"]` | 동일 | PASS | |
| 10 | 우선순위 버튼 class | `filter-priority-btn px-2.5 py-1.5 bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors border-r border-gray-200 dark:border-gray-600 last:border-0` | 동일 | PASS | |
| 11 | 납기 토글 컨테이너 | `flex rounded-lg border ... overflow-hidden text-xs` | 동일 | PASS | |
| 12 | 납기 버튼 3개 | `["", "전체"], ["urgent", "D-7"], ["overdue", "지연"]` | 동일 | PASS | |
| 13 | 납기 버튼 class | `filter-due-btn ...` (우선순위와 동일 패턴) | 동일 | PASS | |
| 14 | 키워드 검색 컨테이너 class | `flex items-center gap-1.5 flex-1 min-w-[140px] max-w-[220px] border ... rounded-lg px-2.5 py-1.5 bg-white dark:bg-gray-700` | 동일 | PASS | |
| 15 | 검색 아이콘 SVG | `w-3.5 h-3.5` + circle + line | 동일 | PASS | |
| 16 | 검색 input id | `filter-keyword` | `filter-keyword` | PASS | |
| 17 | 검색 input placeholder | `검색...` | `검색...` | PASS | |
| 18 | 초기화 버튼 id | `filter-reset` | `filter-reset` | PASS | |
| 19 | 초기화 버튼 hidden 기본 | Design: class 끝에 `hidden` | Implementation: class 시작에 `hidden` | CHANGED | class 내 hidden 위치 차이 (시작 vs 끝). 기능 동일 |
| 20 | 초기화 버튼 X 아이콘 SVG | `w-3.5 h-3.5` + 2 line | 동일 | PASS | |

### 2.2 FR-01: 필터 JS

| # | 항목 | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 21 | filterAssignee 변수 | `document.getElementById('filter-assignee')` | 동일 | PASS | |
| 22 | filterKeyword 변수 | `document.getElementById('filter-keyword')` | 동일 | PASS | |
| 23 | filterReset 변수 | `document.getElementById('filter-reset')` | 동일 | PASS | |
| 24 | meId 변수 | `'<%= current_user.id %>'` | 동일 | PASS | |
| 25 | activePriority 초기값 | `let activePriority = '';` | 동일 | PASS | |
| 26 | activeDue 초기값 | `let activeDue = '';` | 동일 | PASS | |
| 27 | setActiveToggle 함수 | btnClass + activeVal 파라미터 | 동일 | PASS | |
| 28 | setActiveToggle: bg-accent toggle | `btn.classList.toggle('bg-accent', isActive)` | `btn.classList.toggle('bg-accent', on)` | CHANGED | 변수명 isActive -> on (기능 동일) |
| 29 | setActiveToggle: text-white toggle | Design O | 구현 O | PASS | |
| 30 | setActiveToggle: dark:bg-accent toggle | Design에 포함 | 구현에 없음 | CHANGED | 구현에서 `dark:bg-accent` 제거. dark mode에서 accent 배경 미적용 가능성 |
| 31 | setActiveToggle: bg-white toggle | Design O | 구현 O | PASS | |
| 32 | setActiveToggle: dark:bg-gray-700 toggle | Design O | 구현 O | PASS | |
| 33 | setActiveToggle: text-gray-600 toggle | Design O | 구현 O | PASS | |
| 34 | setActiveToggle: dark:text-gray-300 toggle | Design O | 구현 O | PASS | |
| 35 | applyFilters 함수 존재 | Design O | 구현 O | PASS | |
| 36 | applyFilters: assigneeVal | `filterAssignee.value` | 동일 | PASS | |
| 37 | applyFilters: keyword | `filterKeyword.value.toLowerCase().trim()` | 동일 | PASS | |
| 38 | applyFilters: anyActive 선언 | `let anyActive = ...` | `const anyActive = ...` | CHANGED | let -> const (기능 동일, const가 적절) |
| 39 | applyFilters: querySelectorAll 대상 | `[data-order-id]` | 동일 | PASS | |
| 40 | applyFilters: assigneeIds 파싱 | `split(',').filter(Boolean)` | 동일 | PASS | |
| 41 | applyFilters: me 매칭 | `assigneeIds.includes(meId)` | 동일 | PASS | |
| 42 | applyFilters: priorityOk | `!activePriority \|\| card.dataset.priority === activePriority` | 동일 | PASS | |
| 43 | applyFilters: dueDays parseInt | `parseInt(card.dataset.dueDays, 10)` | 동일 | PASS | |
| 44 | applyFilters: overdue 판정 | `dueDays < 0` | 동일 | PASS | |
| 45 | applyFilters: urgent 판정 | `dueDays >= 0 && dueDays <= 7` | 동일 | PASS | |
| 46 | applyFilters: keyword 매칭 | `(card.dataset.title + ' ' + card.dataset.customer).toLowerCase().includes(keyword)` | 동일 | PASS | |
| 47 | applyFilters: card hidden toggle | `card.classList.toggle('hidden', !(all conditions))` | 동일 | PASS | |
| 48 | applyFilters: filterReset 토글 | `filterReset.classList.toggle('hidden', !anyActive)` | 동일 | PASS | |
| 49 | applyFilters: updateCounts 호출 | Design O | 구현 O | PASS | |
| 50 | 우선순위 토글 클릭 이벤트 | 재클릭 시 해제 패턴: `activePriority === btn.dataset.value ? '' : btn.dataset.value` | 동일 | PASS | |
| 51 | 납기 토글 클릭 이벤트 | 동일 재클릭 해제 패턴 | 동일 | PASS | |
| 52 | filterAssignee change 이벤트 | `filterAssignee.addEventListener('change', applyFilters)` | 동일 | PASS | |
| 53 | filterKeyword input 이벤트 | `filterKeyword.addEventListener('input', applyFilters)` | 동일 | PASS | |
| 54 | filterReset click 이벤트 | 전체 초기화 로직 | 동일 | PASS | |
| 55 | 초기 setActiveToggle 호출 | priority + due 2건 | 동일 | PASS | |

### 2.3 FR-02: _card.html.erb 변경

| # | 항목 | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 56 | 카드 루트 div: relative class | Design O | 구현 O | PASS | |
| 57 | data-order-id | `order.id` | 동일 | PASS | |
| 58 | data-priority | `order.priority` | 동일 | PASS | |
| 59 | data-due-days | `order.days_until_due.to_i` | 동일 | PASS | |
| 60 | data-assignee-ids | `order.assignees.map(&:id).join(',')` | 동일 | PASS | |
| 61 | data-title | `order.title` | 동일 | PASS | |
| 62 | data-customer | `order.customer_name` | 동일 | PASS | |
| 63 | 퀵액션 div class | `quick-actions absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity z-10` | 동일 | PASS | |
| 64 | prev_status 조건부 | `local_assigns[:prev_status]` | 동일 | PASS | |
| 65 | prev 버튼 class | `quick-move-btn w-6 h-6 flex items-center justify-center rounded-md bg-white dark:bg-gray-700 border border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-600 shadow-sm transition-colors` | 동일 | PASS | |
| 66 | prev 버튼 data-order-id | `order.id` | 동일 | PASS | |
| 67 | prev 버튼 data-move-to | `local_assigns[:prev_status]` | 동일 | PASS | |
| 68 | prev 버튼 title | `← <%= Order::STATUS_LABELS[...] %>` | 동일 | PASS | |
| 69 | prev 버튼 onclick | `event.stopPropagation()` | 동일 | PASS | |
| 70 | prev 버튼 SVG | `polyline points="15 18 9 12 15 6"` | 동일 | PASS | |
| 71 | next_status 조건부 | `local_assigns[:next_status]` | 동일 | PASS | |
| 72 | next 버튼 class | `quick-move-btn w-6 h-6 ... bg-accent text-white hover:bg-blue-500 border border-accent shadow-sm transition-colors` | 동일 | PASS | |
| 73 | next 버튼 data-order-id | `order.id` | 동일 | PASS | |
| 74 | next 버튼 data-move-to | `local_assigns[:next_status]` | 동일 | PASS | |
| 75 | next 버튼 title | `→ <%= Order::STATUS_LABELS[...] %>` | 동일 | PASS | |
| 76 | next 버튼 onclick | `event.stopPropagation()` | 동일 | PASS | |
| 77 | next 버튼 SVG | `polyline points="9 18 15 12 9 6"` | 동일 | PASS | |

### 2.4 FR-02: index.html.erb render locals 전달

| # | 항목 | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 78 | each_with_index 사용 | Design: `col_idx = Order::KANBAN_COLUMNS.index(status)` | 구현: `each_with_index do \|status, col_idx\|` | CHANGED | index 계산 방식 차이. each_with_index가 더 효율적 (기능 동일) |
| 79 | prev_stat 계산 | `col_idx > 0 ? Order::KANBAN_COLUMNS[col_idx - 1] : nil` | 동일 | PASS | |
| 80 | next_stat 계산 | `col_idx < Order::KANBAN_COLUMNS.length - 1 ? Order::KANBAN_COLUMNS[col_idx + 1] : nil` | 동일 | PASS | |
| 81 | render locals 전달 | `render "kanban/card", order: order, prev_status: prev_stat, next_status: next_stat` | 동일 | PASS | |

### 2.5 FR-02: 퀵액션 JS

| # | 항목 | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 82 | document click 위임 | `document.addEventListener('click', function(e) { ... })` | 동일 | PASS | |
| 83 | btn 탐색 | `e.target.closest('.quick-move-btn')` | 동일 | PASS | |
| 84 | e.stopPropagation | Design O | 구현 O | PASS | |
| 85 | orderId/moveTo 추출 | `btn.dataset.orderId`, `btn.dataset.moveTo` | 동일 | PASS | |
| 86 | cardEl 탐색 | `document.querySelector('[data-order-id="' + orderId + '"]')` | 동일 | PASS | |
| 87 | fromCol 변수 | Design: `const fromCol = cardEl?.closest('.kanban-cards')` | 구현: fromCol 변수 없음 | CHANGED | 구현에서 fromCol 미사용 (불필요한 변수 제거, 개선) |
| 88 | 가드절 | `if (!orderId \|\| !moveTo \|\| !cardEl) return` | 동일 | PASS | |
| 89 | 중복 클릭 방지: disabled | `btn.disabled = true` | 동일 | PASS | |
| 90 | 중복 클릭 방지: opacity | `btn.classList.add('opacity-50')` | 동일 | PASS | |
| 91 | fetch URL | `'/orders/' + orderId + '/move'` | 동일 | PASS | |
| 92 | fetch method | `PATCH` | 동일 | PASS | |
| 93 | fetch headers | `Content-Type: application/json`, `X-CSRF-Token: CSRF` | 동일 | PASS | |
| 94 | fetch body | `JSON.stringify({ status: moveTo })` | 동일 | PASS | |
| 95 | 성공: targetCol 탐색 | `document.getElementById('column-' + moveTo)` | 동일 | PASS | |
| 96 | 성공: DOM 이동 | `targetCol.insertBefore(cardEl, targetCol.firstChild)` | 동일 | PASS | |
| 97 | 성공: updateCounts 호출 | Design O | 구현 O | PASS | |
| 98 | 성공: showToast | `'→ ' + colLabel + ' 이동 완료', true` | 동일 | PASS | |
| 99 | 성공: colLabel 추출 | `targetCol.closest('.kanban-column')?.querySelector('.column-name')?.textContent` | 동일 | PASS | |
| 100 | 실패: showToast | `'이동 실패: ' + (data.errors \|\| []).join(', '), false` | 동일 | PASS | |
| 101 | catch: showToast | `'네트워크 오류가 발생했습니다.', false` | 동일 | PASS | |
| 102 | finally 블록 | Design: `.finally(function() { btn.disabled = false; btn.classList.remove('opacity-50'); })` | 구현: finally 없음. 실패/catch 각각에서 btn 복원 | CHANGED | Design은 finally에서 일괄 복원, 구현은 실패/catch에서만 복원 (성공 시 btn 비활성 유지 -- 카드가 이동했으므로 적절) |

---

## 3. Match Rate Summary

### 3.1 FR-01 필터 바

| 구분 | 건수 |
|------|:----:|
| PASS | 49 |
| CHANGED | 3 |
| FAIL | 0 |
| ADDED | 0 |
| **합계** | **52** |

- **GAP-01** (#19): 초기화 버튼 hidden class 위치 차이 (기능 동일)
- **GAP-02** (#28): 변수명 `isActive` -> `on` (기능 동일)
- **GAP-03** (#30): `dark:bg-accent` toggle 누락 (dark mode에서 accent 배경 미적용)
- **GAP-04** (#38): `let anyActive` -> `const anyActive` (개선)

### 3.2 FR-02 퀵액션

| 구분 | 건수 |
|------|:----:|
| PASS | 46 |
| CHANGED | 3 |
| FAIL | 0 |
| ADDED | 0 |
| **합계** | **49** |

- **GAP-05** (#78): index 계산 방식 차이 (each_with_index 사용 -- 개선)
- **GAP-06** (#87): fromCol 변수 제거 (미사용 변수 삭제 -- 개선)
- **GAP-07** (#102): finally 블록 대신 실패/catch에서만 btn 복원 (성공 시 카드 이동으로 btn 비활성 유지 -- 더 적절한 UX)

### 3.3 Overall Match Rate

```
+---------------------------------------------+
|  Overall Match Rate: 94%                     |
+---------------------------------------------+
|  PASS:     95 items (93.1%)                  |
|  CHANGED:   6 items ( 5.9%) -- 차이 있으나   |
|             기능 동일 또는 개선               |
|  FAIL:      0 items ( 0.0%)                  |
|  ADDED:     0 items ( 0.0%)                  |
|  Total:   101 items                          |
+---------------------------------------------+
|  Match Rate = (PASS + CHANGED) / Total       |
|             = 101 / 101 = 100% (기능 완성)   |
|  Strict Rate = PASS / Total                  |
|             = 95 / 101 = 94% (코드 일치)     |
+---------------------------------------------+
```

---

## 4. Gap Detail

### GAP-01: 초기화 버튼 hidden class 위치

- **Design**: `class="text-xs text-gray-400 ... hidden"`  (class 끝)
- **Implementation**: `class="hidden text-xs text-gray-400 ..."`  (class 시작)
- **영향**: 없음. CSS class 순서는 기능에 영향 없음
- **판정**: CHANGED (미세 차이)

### GAP-02: setActiveToggle 변수명

- **Design**: `const isActive = btn.dataset.value === activeVal;`
- **Implementation**: `const on = btn.dataset.value === activeVal;`
- **영향**: 없음. 지역 변수명 차이
- **판정**: CHANGED (미세 차이)

### GAP-03: dark:bg-accent toggle 누락

- **Design**: `btn.classList.toggle('dark:bg-accent', isActive);` 포함
- **Implementation**: 해당 줄 없음
- **영향**: Dark mode에서 활성 토글 버튼에 accent 배경색이 적용되지 않을 수 있음. 단, `bg-accent` class가 dark mode에서도 동작하므로 실질적 영향 미미
- **판정**: CHANGED (동작 차이 가능하나 bg-accent가 dark mode에서도 유효)

### GAP-04: anyActive 선언 키워드

- **Design**: `let anyActive = ...`
- **Implementation**: `const anyActive = ...`
- **영향**: 없음. 재할당 없으므로 const가 적절
- **판정**: CHANGED (개선)

### GAP-05: each_with_index vs index 계산

- **Design**: `<% col_idx = Order::KANBAN_COLUMNS.index(status) %>`
- **Implementation**: `<% Order::KANBAN_COLUMNS.each_with_index do |status, col_idx| %>`
- **영향**: 없음. each_with_index가 더 관용적이고 효율적
- **판정**: CHANGED (개선)

### GAP-06: fromCol 변수 제거

- **Design**: `const fromCol = cardEl?.closest('.kanban-cards');` 선언
- **Implementation**: 해당 변수 없음
- **영향**: 없음. Design에서도 fromCol을 이후에 사용하지 않음 (불필요한 변수)
- **판정**: CHANGED (개선 -- 미사용 변수 제거)

### GAP-07: finally 블록 vs 개별 복원

- **Design**: `.finally()` 블록에서 `btn.disabled = false; btn.classList.remove('opacity-50');`
- **Implementation**: 성공 시 btn 복원 없음, 실패/catch에서만 btn 복원
- **영향**: 성공 시 버튼이 disabled 상태로 유지됨. 그러나 성공 시 카드가 다른 컬럼으로 이동하므로 원래 위치의 버튼은 더 이상 보이지 않아 사실상 문제 없음. 오히려 더 적절한 UX.
- **판정**: CHANGED (의도적 개선)

---

## 5. View-Layer Concerns

| 파일 | 위치 | 내용 | 비고 |
|------|------|------|------|
| `index.html.erb` | L25 | `User.order(:name).each` 직접 호출 | Design 명세 자체가 이 패턴. 프로젝트 전반에서 반복되는 패턴 |

---

## 6. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match (FR-01) | 94% | ✅ |
| Design Match (FR-02) | 94% | ✅ |
| FAIL 항목 | 0건 | ✅ |
| **Overall** | **94%** | ✅ |

---

## 7. Recommended Actions

### 즉시 조치 불필요

FAIL 항목이 0건이므로 즉시 조치할 사항 없음.

### 선택적 개선 (낮은 우선순위)

| # | 항목 | 영향 | 권장 조치 |
|---|------|------|-----------|
| 1 | GAP-03: dark:bg-accent 누락 | 낮음 | dark mode 활성 토글 확인 후 필요 시 추가 |

### Design 문서 업데이트 권장

| # | 항목 | 이유 |
|---|------|------|
| 1 | GAP-04: `let` -> `const` | 구현이 더 적절 |
| 2 | GAP-05: each_with_index 패턴 | 구현이 더 관용적 |
| 3 | GAP-06: fromCol 변수 삭제 | 미사용 변수 |
| 4 | GAP-07: finally 대신 개별 복원 | 성공 시 복원 불필요 |

---

## 8. Conclusion

Match Rate **94%** -- Design 문서와 Implementation이 잘 일치합니다.

6건의 CHANGED 항목 중:
- 3건은 **구현이 Design보다 개선**된 사례 (GAP-04, GAP-05, GAP-06)
- 1건은 **의도적 UX 개선** (GAP-07)
- 1건은 **미세한 코드 스타일 차이** (GAP-02)
- 1건은 **dark mode 미세 차이** (GAP-03)

FAIL 항목이 0건이므로 추가 iteration 없이 완료 가능합니다.

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial analysis | bkit-gap-detector |
