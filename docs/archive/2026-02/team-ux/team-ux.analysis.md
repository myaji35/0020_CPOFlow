# team-ux Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Design Doc**: [team-ux.design.md](../02-design/features/team-ux.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

team-ux 기능(팀 현황 UX 강화)의 Design 문서와 실제 구현 코드 간 차이를 검출하고 Match Rate를 산출한다.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/team-ux.design.md`
- **Implementation Files**:
  - `app/controllers/team_controller.rb`
  - `app/views/team/index.html.erb`
  - `app/views/team/show.html.erb`
- **FR Coverage**: FR-01 (통계 바), FR-02 (워크로드 카드 강화), FR-03 (팀원 상세 강화)

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 Controller: index action (FR-01 + FR-02)

| # | Item | Design (L43-65) | Implementation (L1-23) | Status |
|---|------|-----------------|------------------------|--------|
| 01 | User.order(:branch, :name) | O | O | PASS |
| 02 | includes(:assigned_orders, :tasks) | O | O | PASS |
| 03 | active = u.assigned_orders.active.to_a | O | O | PASS |
| 04 | active_orders count | O | O | PASS |
| 05 | tasks_pending: u.tasks.pending.count | O | O | PASS |
| 06 | overdue_orders: active.count { due_date < today } | O | O | PASS |
| 07 | urgent_orders: active.count { due_date >= today && <= today+7 } | O | O | PASS |
| 08 | @summary[:total_members] | O | O | PASS |
| 09 | @summary[:total_active] | O | O | PASS |
| 10 | @summary[:total_overdue] | O | O | PASS |
| 11 | @summary[:overloaded] (>= 8) | O | O | PASS |

### 2.2 Controller: show action (FR-03)

| # | Item | Design (L67-76) | Implementation (L25-34) | Status |
|---|------|-----------------|-------------------------|--------|
| 12 | @member = User.find(params[:id]) | O | O | PASS |
| 13 | @overdue_orders = assigned_orders.overdue.by_due_date | O | O | PASS |
| 14 | @overdue_orders includes(:client, :project) | O | O | PASS |
| 15 | @active_orders where(due_date >= today OR NULL) | O | O | PASS |
| 16 | @active_orders .by_due_date.limit(20) | O | O | PASS |
| 17 | @active_orders includes(:client, :project) | O | O | PASS |
| 18 | @status_counts = group(:status).count | O | O | PASS |

### 2.3 FR-01: Team Summary Bar (index.html.erb)

| # | Item | Design (L88-105) | Implementation (L13-30) | Status |
|---|------|-----------------|-------------------------|--------|
| 19 | grid grid-cols-4 gap-3 | O | O | PASS |
| 20 | Card 1: total_members (white bg) | O | O | PASS |
| 21 | Card 2: total_active (blue bg) | O | O | PASS |
| 22 | Card 3: total_overdue (red bg) | O | O | PASS |
| 23 | Card 4: overloaded (orange bg) | O | O | PASS |
| 24 | 카드 텍스트 (총 팀원/총 진행 주문/지연 주문/과부하 팀원) | O | O | PASS |
| 25 | text-2xl font-bold | O | O | PASS |
| 26 | dark mode 클래스 | O | O | PASS |

### 2.4 FR-02: Workload Card Enhancement (index.html.erb)

| # | Item | Design (L117-187) | Implementation (L33-97) | Status |
|---|------|-------------------|--------------------------|--------|
| 27 | is_overloaded = w[:active_orders] >= 8 | O | O | PASS |
| 28 | 과부하 시 border-red-300 dark:border-red-700 | O | O | PASS |
| 29 | 정상 시 border-gray-200 hover:border-primary/30 | O | O | PASS |
| 30 | user.initials 아바타 | O | O | PASS |
| 31 | user.display_name | O | O | PASS |
| 32 | role 배지 (admin/manager/member) | O | O | PASS |
| 33 | branch 표시 | O | O | PASS |
| 34 | 과부하 배지 ("과부하" text) | O | O | PASS |
| 35 | 과부하 배지 스타일 (bg-red-100, text-red-600, rounded-full) | O | O | PASS |
| 36 | grid grid-cols-4 gap-2 (4개 숫자 카드) | O | O | PASS |
| 37 | Card 1: active_orders (gray bg, "진행") | O | O | PASS |
| 38 | Card 2: overdue_orders (red bg, "지연") | O | O | PASS |
| 39 | Card 3: urgent_orders (orange bg, "D-7") | O | O | PASS |
| 40 | Card 4: tasks_pending (gray bg, "태스크") | O | O | PASS |
| 41 | load_pct = [[w[:active_orders]*10, 100].min, 0].max | O | O | PASS |
| 42 | 워크로드 바: >= 8 bg-red-400 | O | O | PASS |
| 43 | 워크로드 바: >= 5 bg-orange-400 | O | O | PASS |
| 44 | 워크로드 바: < 5 bg-green-400 | O | O | PASS |
| 45 | 워크로드 퍼센트 표시 | O | O | PASS |
| 46 | h-1.5 rounded-full 바 높이 | O | O | PASS |
| 47 | 이름 영역 flex items-center gap-3 + min-w-0 | Design: div 분리 | 구현: 부모 div에 min-w-0 합침 | CHANGED |

### 2.5 FR-03: Show -- Overdue Orders Section

| # | Item | Design (L196-228) | Implementation (L42-76) | Status |
|---|------|-------------------|--------------------------|--------|
| 48 | @overdue_orders.any? 조건 | O | O | PASS |
| 49 | border-red-200 dark:border-red-800 | O | O | PASS |
| 50 | bg-red-50 dark:bg-red-900/20 헤더 배경 | O | O | PASS |
| 51 | text-red-700 dark:text-red-400 헤더 텍스트 | O | O | PASS |
| 52 | "지연 주문 (N건)" 헤더 텍스트 | O | O | PASS |
| 53 | openOrderDrawer(id, title.to_json, order_path) | O | O | PASS |
| 54 | order.title 표시 | O | O | PASS |
| 55 | order.client.name / customer_name fallback | O | O | PASS |
| 56 | status_badge(order) | O | O | PASS |
| 57 | priority_badge(order) | O | O | PASS |
| 58 | due_badge(order) | O | O | PASS |
| 59 | hover:bg-gray-50 transition-colors cursor-pointer | O | O | PASS |
| 60 | order.project 표시 (지연 섹션) | Design 미명세 | 구현 O (L62-64) | ADDED |

### 2.6 FR-03: Show -- Active Orders Section

| # | Item | Design (L236-257) | Implementation (L85-108) | Status |
|---|------|-------------------|---------------------------|--------|
| 61 | openOrderDrawer 연동 | O | O | PASS |
| 62 | order.client.name / customer_name fallback | O | O | PASS |
| 63 | order.project.name 표시 | O | O | PASS |
| 64 | status_badge(order) | O | O | PASS |
| 65 | priority_badge(order) | O | O | PASS |
| 66 | due_badge(order) | O | O | PASS |
| 67 | hover + transition-colors + cursor-pointer | O | O | PASS |
| 68 | flex items-center gap-2 shrink-0 (배지 영역) | O | O | PASS |

---

## 3. Gap Detail

### GAP-01: min-w-0 위치 차이 (CHANGED, #47)

| 구분 | 내용 |
|------|------|
| **Design** | `<div class="flex items-center gap-3">` (부모) + `<div class="min-w-0">` (자식, 이름 wrapper) |
| **Implementation** | `<div class="flex items-center gap-3 min-w-0">` (부모에 합침) |
| **Impact** | Low -- 기능적 차이 없음. min-w-0이 부모에 있어도 truncate 동작 동일. 오히려 부모에 적용이 flex 컨테이너에서 더 안정적. |
| **Verdict** | 개선 -- 수정 불필요 |

### GAP-02: 지연 주문 섹션에 project 표시 추가 (ADDED, #60)

| 구분 | 내용 |
|------|------|
| **Design** | 지연 주문 섹션에서 client/customer_name만 표시 (project 미명세) |
| **Implementation** | `order.project` 조건 추가 (show.html.erb L62-64) -- 진행 중 주문과 UI 일관성 확보 |
| **Impact** | None -- UX 개선. 진행 중 주문 섹션에는 Design에서도 project 표시가 있으므로 일관성 확보 목적 |
| **Verdict** | 의도적 개선 -- Design 문서 업데이트 권장 |

---

## 4. Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 97%                     |
+---------------------------------------------+
|  PASS:     66 items (97%)                    |
|  CHANGED:   1 item  ( 1%) -- GAP-01         |
|  ADDED:     1 item  ( 1%) -- GAP-02         |
|  FAIL:      0 items ( 0%)                    |
+---------------------------------------------+
|  Total Checked: 68 items                     |
+---------------------------------------------+
```

---

## 5. FR-level Summary

| FR | Description | Items | PASS | CHANGED | ADDED | FAIL | Rate |
|----|-------------|:-----:|:----:|:-------:|:-----:|:----:|:----:|
| FR-01+02 Controller | index action (@workloads + @summary) | 11 | 11 | 0 | 0 | 0 | 100% |
| FR-03 Controller | show action (@overdue + includes + limit) | 7 | 7 | 0 | 0 | 0 | 100% |
| FR-01 View | Team summary bar 4 cards | 8 | 8 | 0 | 0 | 0 | 100% |
| FR-02 View | Workload card enhancement | 21 | 20 | 1 | 0 | 0 | 95% |
| FR-03 View (overdue) | Overdue orders section | 13 | 12 | 0 | 1 | 0 | 92% |
| FR-03 View (active) | Active orders + badges + drawer | 8 | 8 | 0 | 0 | 0 | 100% |

---

## 6. Completion Criteria Verification

| # | Criteria | Status |
|---|----------|--------|
| 1 | Team summary bar 4 cards (total members / total active / overdue / overloaded) | PASS |
| 2 | Member card 4 stat cards (active / overdue / D-7 / tasks) | PASS |
| 3 | active >= 8 -> "overloaded" badge + red border | PASS |
| 4 | Member detail -- overdue orders separate section (red header) | PASS |
| 5 | Member detail -- status_badge + priority_badge + due_badge | PASS |
| 6 | Member detail -- openOrderDrawer integration | PASS |
| 7 | Gap Analysis Match Rate >= 90% | PASS (97%) |

---

## 7. Recommended Actions

### 7.1 Design Document Update (Optional)

| Priority | Item | Description |
|----------|------|-------------|
| Low | GAP-02 반영 | 지연 주문 섹션 ERB에 `order.project` 조건 추가 (진행 중 주문과 일관성) |

### 7.2 No Immediate Actions Required

FAIL 항목 0건, CHANGED 1건 (기능 영향 없는 CSS 위치 차이), ADDED 1건 (UX 개선).
전체 Match Rate 97%로 완료 기준(90%) 초과 달성.

---

## 8. Overall Score

```
+---------------------------------------------+
|  Category           | Score  | Status        |
+---------------------------------------------+
|  Design Match       |  97%   | PASS          |
|  Controller Logic   | 100%   | PASS          |
|  View FR-01         | 100%   | PASS          |
|  View FR-02         |  95%   | PASS          |
|  View FR-03         |  96%   | PASS          |
|  Completion Criteria|  7/7   | PASS          |
+---------------------------------------------+
|  Overall            |  97%   | PASS          |
+---------------------------------------------+
```

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial gap analysis | bkit-gap-detector |
