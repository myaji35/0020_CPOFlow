# calendar-ux Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Design Doc**: [calendar-ux.design.md](../02-design/features/calendar-ux.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

calendar-ux 기능(FR-01 통계 바, FR-02 날짜 사이드 패널, FR-03 카드 드로어, FR-04 오늘 버튼, FR-05 하단 목록 배지) Design 문서와 실제 구현 코드 간 차이 분석

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/calendar-ux.design.md`
- **Implementation Files**:
  - `app/controllers/calendar_controller.rb`
  - `app/views/calendar/index.html.erb`
- **Analysis Date**: 2026-02-28

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 Controller (FR-01 @stats + includes)

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 1 | class 선언 | `class CalendarController < ApplicationController` | 동일 | PASS | |
| 2 | @month 파싱 | `params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month` | 동일 | PASS | |
| 3 | @orders includes | `.includes(:assignees, :client, :project)` | `.includes(:assignees, :client, :project)` | PASS | Design 명세 반영 완료 |
| 4 | @orders scope | `.by_due_date` | `.by_due_date` | PASS | |
| 5 | @stats[:total] | `@orders.count` | `@orders.count` | PASS | |
| 6 | @stats[:overdue] | `@orders.count { \|o\| o.due_date < today }` | 동일 | PASS | |
| 7 | @stats[:urgent] | `@orders.count { \|o\| o.due_date >= today && o.due_date <= today + 7 }` | 동일 | PASS | |
| 8 | @stats[:normal] | `@orders.count { \|o\| o.due_date > today + 7 }` | 동일 | PASS | |

**Controller Match: 8/8 PASS (100%)**

---

### 2.2 FR-01: 월별 통계 바 ERB

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 9 | 그리드 컨테이너 | `grid grid-cols-4 gap-3` | 동일 | PASS | |
| 10 | 총 마감 카드 bg | `bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 text-center` | 동일 | PASS | |
| 11 | 총 마감 값 | `text-2xl font-bold text-gray-900 dark:text-white` + `@stats[:total]` | 동일 | PASS | |
| 12 | 총 마감 라벨 | `text-xs text-gray-500 dark:text-gray-400 mt-1` + "총 마감" | 동일 | PASS | |
| 13 | 지연 카드 bg | `bg-red-50 dark:bg-red-900/20 rounded-xl border border-red-100 dark:border-red-800 p-4 text-center` | 동일 | PASS | |
| 14 | 지연 값 색상 | `text-2xl font-bold text-red-600 dark:text-red-400` + `@stats[:overdue]` | 동일 | PASS | |
| 15 | 지연 라벨 | `text-xs text-red-500 dark:text-red-400 mt-1` + "지연" | 동일 | PASS | |
| 16 | D-7 카드 bg | `bg-orange-50 dark:bg-orange-900/20 rounded-xl border border-orange-100 dark:border-orange-800 p-4 text-center` | 동일 | PASS | |
| 17 | D-7 값 색상 | `text-2xl font-bold text-orange-600 dark:text-orange-400` + `@stats[:urgent]` | 동일 | PASS | |
| 18 | D-7 라벨 | `text-xs text-orange-500 dark:text-orange-400 mt-1` + "D-7 이내" | 동일 | PASS | |
| 19 | 정상 카드 bg | `bg-green-50 dark:bg-green-900/20 rounded-xl border border-green-100 dark:border-green-800 p-4 text-center` | 동일 | PASS | |
| 20 | 정상 값 색상 | `text-2xl font-bold text-green-600 dark:text-green-400` + `@stats[:normal]` | 동일 | PASS | |
| 21 | 정상 라벨 | `text-xs text-green-500 dark:text-green-400 mt-1` + "정상" | 동일 | PASS | |

**FR-01 Match: 13/13 PASS (100%)**

---

### 2.3 FR-04: 오늘 버튼

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 22 | link_to target | `calendar_path` (파라미터 없음 = 오늘 달) | `calendar_path` | PASS | |
| 23 | 텍스트 | `"오늘"` | `"오늘"` | PASS | |
| 24 | class | `text-xs px-3 py-1.5 rounded-lg border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors` | 동일 | PASS | |
| 25 | 배치 순서 | 이전/다음 화살표 앞 | 이전/다음 화살표 앞 | PASS | |

**FR-04 Match: 4/4 PASS (100%)**

---

### 2.4 FR-02: 날짜 셀 data 속성

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 26 | data-calendar-date | `date.strftime('%Y-%m-%d')` | 동일 | PASS | |
| 27 | data-orders JSON | `html_escape(day_orders_json)` | 동일 | PASS | |
| 28 | day_orders_json 필드: id | `o.id` | `o.id` | PASS | |
| 29 | day_orders_json 필드: title | `o.title` | `o.title` | PASS | |
| 30 | day_orders_json 필드: path | `order_path(o)` | `order_path(o)` | PASS | |
| 31 | day_orders_json 필드: status | `Order::STATUS_LABELS[o.status]` | `Order::STATUS_LABELS[o.status]` | PASS | |
| 32 | day_orders_json 필드: priority | `o.priority` | `o.priority` | PASS | |
| 33 | day_orders_json 필드: due_date | `o.due_date.strftime("%m/%d")` | **누락** | CHANGED | Design에는 due_date 필드 포함, 구현에서는 생략. 사이드 패널 JS에서 due_date 미사용이므로 기능 영향 없음 |
| 34 | 셀 cursor | `cursor-pointer` | `cursor-pointer` | PASS | |
| 35 | 셀 hover | `hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors` | 동일 | PASS | |
| 36 | 이번달/타달 bg | `is_current_month ? 'bg-white dark:bg-gray-800' : 'bg-gray-50 dark:bg-gray-700/30'` | 동일 | PASS | |
| 37 | 오늘 ring | `is_today ? 'ring-2 ring-inset ring-primary/30' : ''` | 동일 | PASS | |
| 38 | 날짜 표시 span | 오늘: `w-6 h-6 bg-primary text-white rounded-full flex items-center justify-center` | 동일 | PASS | |

**FR-02 날짜 셀: 12 PASS + 1 CHANGED = 12/13 (92%)**

---

### 2.5 FR-03: 카드 onclick -> openOrderDrawer

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 39 | 카드 element | `<div>` (기존 link_to 제거) | `<div>` | PASS | |
| 40 | event.stopPropagation() | `onclick="event.stopPropagation(); openOrderDrawer(..."` | 동일 | PASS | |
| 41 | openOrderDrawer 인자 | `order.id, order.title.to_json, order_path(order)` | 동일 | PASS | |
| 42 | priority urgent 색상 | `bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400` | 동일 | PASS | |
| 43 | priority high 색상 | `bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-400` | 동일 | PASS | |
| 44 | priority else 색상 | `bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400` | 동일 | PASS | |
| 45 | 카드 공통 class | `block text-xs truncate px-1.5 py-0.5 rounded mb-0.5 cursor-pointer` | 동일 | PASS | |
| 46 | first(3) 제한 | `day_orders.first(3).each` | 동일 | PASS | |
| 47 | +N more 텍스트 | `text-xs text-gray-400 dark:text-gray-500` + `day_orders.size - 3` | 동일 | PASS | |

**FR-03 Match: 9/9 PASS (100%)**

---

### 2.6 FR-02: 사이드 패널 HTML

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 48 | overlay id | `calendar-panel-overlay` | 동일 | PASS | |
| 49 | overlay class | `fixed inset-0 z-40 hidden` | 동일 | PASS | |
| 50 | side-panel id | `calendar-side-panel` | 동일 | PASS | |
| 51 | side-panel class | `fixed top-0 right-0 h-full w-80 bg-white dark:bg-gray-900 border-l border-gray-200 dark:border-gray-700 shadow-xl z-50 transform translate-x-full transition-transform duration-200 flex flex-col` | 동일 | PASS | |
| 52 | header 구조 | `flex items-center justify-between px-4 py-4 border-b border-gray-100 dark:border-gray-700` | 동일 | PASS | |
| 53 | panel-date-title | `h3 id="panel-date-title" class="text-sm font-semibold text-gray-900 dark:text-white"` | 동일 | PASS | |
| 54 | close button id | `calendar-panel-close` | 동일 | PASS | |
| 55 | close button class | `p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors` | 동일 | PASS | |
| 56 | close SVG | `w-4 h-4 text-gray-500` + line x1=18 y1=6 x2=6 y2=18 / line x1=6 y1=6 x2=18 y2=18 | 동일 | PASS | |
| 57 | orders list id | `panel-orders-list` | 동일 | PASS | |
| 58 | orders list class | `flex-1 overflow-y-auto py-2` | 동일 | PASS | |

**FR-02 HTML Match: 11/11 PASS (100%)**

---

### 2.7 FR-02: 사이드 패널 JS

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 59 | 변수 선언 키워드 | `const` | `var` | CHANGED | Design은 const 사용, 구현은 var 사용. ES6 const가 더 엄격하나, DOMContentLoaded 스코프 내에서 기능 동일 |
| 60 | sidePanel | `document.getElementById('calendar-side-panel')` | 동일 | PASS | |
| 61 | panelTitle | `document.getElementById('panel-date-title')` | 동일 | PASS | |
| 62 | panelList | `document.getElementById('panel-orders-list')` | 동일 | PASS | |
| 63 | panelClose | `document.getElementById('calendar-panel-close')` | 동일 | PASS | |
| 64 | overlay | `document.getElementById('calendar-panel-overlay')` | 동일 | PASS | |
| 65 | PRIORITY_COLORS.urgent | `bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400` | 동일 | PASS | |
| 66 | PRIORITY_COLORS.high | `bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400` | 동일 | PASS | |
| 67 | PRIORITY_COLORS.medium | `bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400` | 동일 | PASS | |
| 68 | PRIORITY_COLORS.low | `bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400` | 동일 | PASS | |
| 69 | openDatePanel title | `dateStr + ' 마감 (' + orders.length + '건)'` | 동일 | PASS | |
| 70 | 빈 목록 메시지 | `마감 주문 없음` class `text-xs text-gray-400 text-center py-8` | 동일 | PASS | |
| 71 | order item class | `flex items-center gap-3 px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer transition-colors border-b border-gray-50 dark:border-gray-700/50` | 동일 | PASS | |
| 72 | order item onclick | `openOrderDrawer(o.id, JSON.stringify(o.title), o.path)` | 동일 | PASS | |
| 73 | title 표시 | `text-sm font-medium text-gray-900 dark:text-white truncate` | 동일 | PASS | |
| 74 | status 표시 | `text-xs text-gray-500 dark:text-gray-400 mt-0.5` + `o.status` | 동일 | PASS | |
| 75 | priority 배지 | `text-xs font-semibold px-2 py-0.5 rounded-full` + priColor + `o.priority.toUpperCase()` | 동일 | PASS | |
| 76 | overlay hidden 제거 | `overlay.classList.remove('hidden')` | 동일 | PASS | |
| 77 | requestAnimationFrame | `sidePanel.classList.remove('translate-x-full')` | 동일 | PASS | |
| 78 | closeDatePanel | `sidePanel.classList.add('translate-x-full')` + `overlay.classList.add('hidden')` | 동일 | PASS | |
| 79 | 셀 클릭 이벤트 | `document.querySelectorAll('[data-calendar-date]').forEach(...)` | 동일 | PASS | |
| 80 | 셀 클릭 핸들러 | `JSON.parse(cell.dataset.orders \|\| '[]')` + `openDatePanel(...)` | 동일 | PASS | |
| 81 | panelClose 이벤트 | `panelClose.addEventListener('click', closeDatePanel)` | 동일 | PASS | |
| 82 | overlay 이벤트 | `overlay.addEventListener('click', closeDatePanel)` | 동일 | PASS | |
| 83 | Escape 키 이벤트 | `document.addEventListener('keydown', ... e.key === 'Escape')` | 동일 | PASS | |

**FR-02 JS Match: 24 PASS + 1 CHANGED = 24/25 (96%)**

---

### 2.8 FR-05: 하단 목록 배지 강화

| # | Item | Design | Implementation | Status | Notes |
|:-:|------|--------|----------------|:------:|-------|
| 84 | 행 onclick | `openOrderDrawer(order.id, order.title.to_json, order_path(order))` | 동일 | PASS | |
| 85 | 행 class | `flex items-center justify-between px-5 py-3 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors cursor-pointer` | 동일 | PASS | |
| 86 | 날짜 day 표시 | `text-lg font-bold text-gray-900 dark:text-white` + `order.due_date.day` | 동일 | PASS | |
| 87 | 날짜 요일 표시 | `text-xs text-gray-400 dark:text-gray-500` + `order.due_date.strftime("%a")` | 동일 | PASS | |
| 88 | title 표시 | `text-sm font-medium text-gray-900 dark:text-white truncate` | 동일 | PASS | |
| 89 | client 분기 (client 있을 때) | `order.client` -> `text-xs text-blue-600 dark:text-blue-400` + `order.client.name` | 동일 | PASS | |
| 90 | client 분기 (customer_name) | `order.customer_name.present?` -> `text-xs text-gray-500 dark:text-gray-400` | 동일 | PASS | |
| 91 | project 표시 | `order.project` -> `text-xs text-green-600 dark:text-green-400` + `order.project.name` | 동일 | PASS | |
| 92 | status_badge | `<%= status_badge(order) %>` | 동일 | PASS | |
| 93 | priority_badge | `<%= priority_badge(order) %>` | 동일 | PASS | |
| 94 | due_badge | `<%= due_badge(order) %>` | 동일 | PASS | |
| 95 | 배지 컨테이너 | `flex items-center gap-2 shrink-0` | 동일 | PASS | |

**FR-05 Match: 12/12 PASS (100%)**

---

## 3. Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 98%                     |
+---------------------------------------------+
|  PASS:     93 items (98%)                    |
|  CHANGED:   2 items  (2%)                    |
|  FAIL:      0 items  (0%)                    |
|  ADDED:     0 items  (0%)                    |
+---------------------------------------------+
```

| FR | Items | PASS | CHANGED | FAIL | Rate |
|:---|:-----:|:----:|:-------:|:----:|:----:|
| Controller | 8 | 8 | 0 | 0 | 100% |
| FR-01 통계 바 | 13 | 13 | 0 | 0 | 100% |
| FR-02 날짜 셀 data | 13 | 12 | 1 | 0 | 92% |
| FR-02 사이드 패널 HTML | 11 | 11 | 0 | 0 | 100% |
| FR-02 사이드 패널 JS | 25 | 24 | 1 | 0 | 96% |
| FR-03 카드 onclick | 9 | 9 | 0 | 0 | 100% |
| FR-04 오늘 버튼 | 4 | 4 | 0 | 0 | 100% |
| FR-05 하단 목록 배지 | 12 | 12 | 0 | 0 | 100% |
| **Total** | **95** | **93** | **2** | **0** | **98%** |

---

## 4. CHANGED Items Detail

### GAP-01: day_orders_json due_date 필드 누락 (Low)

| Item | Value |
|------|-------|
| Design | `{ id, title, path, status, priority, due_date: o.due_date.strftime("%m/%d") }` |
| Implementation | `{ id, title, path, status, priority }` -- due_date 필드 없음 |
| File | `app/views/calendar/index.html.erb` L71-74 |
| Impact | **Low** -- 사이드 패널 JS (`openDatePanel`)에서 `o.due_date`를 참조하지 않으므로 기능 영향 없음. 향후 패널에 날짜 표시를 추가하려면 필요 |
| Action | 선택적 수정 가능 (데이터 완전성을 위해 추가 권장) |

### GAP-02: JS 변수 선언 const vs var (Low)

| Item | Value |
|------|-------|
| Design | `const sidePanel = ...`, `const panelTitle = ...` 등 (ES6 const) |
| Implementation | `var sidePanel = ...`, `var panelTitle = ...` 등 (ES5 var) |
| File | `app/views/calendar/index.html.erb` L169-173, L175 |
| Impact | **Low** -- DOMContentLoaded 스코프 내에서 재할당이 발생하지 않으므로 기능 동일. var는 function-scoped, const는 block-scoped이나 이 컨텍스트에서 차이 없음 |
| Action | 프로젝트 전반에서 var를 사용하는 패턴이므로 의도적 차이로 판단 |

---

## 5. Architecture / Convention Notes

### 5.1 View-Layer Concern
- 없음. 모든 데이터(`@orders`, `@stats`)는 컨트롤러에서 집계하여 뷰에 전달

### 5.2 N+1 Query
- `includes(:assignees, :client, :project)` -- Design 명세대로 eager loading 적용 완료

### 5.3 Helper 재사용
- `status_badge`, `priority_badge`, `due_badge` -- 기존 ApplicationHelper 헬퍼 활용 (FR-05)
- `openOrderDrawer` -- 기존 layout 전역 함수 활용 (FR-03)

---

## 6. Recommended Actions

### 6.1 선택적 개선 (Optional)

| Priority | Item | File | Notes |
|----------|------|------|-------|
| Low | day_orders_json에 due_date 필드 추가 | `calendar/index.html.erb` L74 | 데이터 완전성 + 향후 확장 대비 |
| Low | var -> const 변환 | `calendar/index.html.erb` L169-175 | ES6 모던 패턴. 단, 프로젝트 전반 var 사용 컨벤션과 일관성 고려 필요 |

---

## 7. Conclusion

Calendar UX 기능은 **Match Rate 98%** 로 Design 문서와 매우 높은 일치도를 보입니다.

- FAIL 항목 0건 -- 모든 FR(01~05)이 Design 명세대로 구현됨
- CHANGED 2건 모두 Low impact -- 기능 동작에 영향 없음
- 컨트롤러 @stats 집계, includes 보강, 사이드 패널 HTML/JS, 오늘 버튼, 하단 목록 배지 모두 Design 라인 단위 일치
- Escape/외부클릭 패널 닫기 JS 정상 구현 확인

**Match Rate >= 90% 달성 -- Check 단계 통과**

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial analysis | bkit-gap-detector |
