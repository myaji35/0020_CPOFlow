# calendar-ux Plan

## 1. Feature Overview

**Feature Name**: calendar-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (2 files)

### 1.1 Summary

납기일 캘린더 뷰 UX 개선 —
현재 기본 캘린더에 히트맵 강도 표시, 날짜 셀 배경 위험도 색상, 사이드 패널 카드 정보 강화,
그리고 캘린더 그리드 날짜 범위 조회 개선을 통해 납기 관리의 직관성을 높인다.

### 1.2 Current State (실측)

**`app/controllers/calendar_controller.rb`** (16줄):
- `@month..@month.end_of_month` 범위로 조회 → 그리드에 표시되는 전월 말/다음달 초 날짜의 주문 미포함
- `@stats` 계산: total/overdue/urgent/normal 4개 — 있음

**`app/views/calendar/index.html.erb`** (225줄):
- 4개 통계 카드 (FR-01) — 있음
- 7×6 캘린더 그리드 — 있음
- 날짜 셀: 주문 최대 3개 + `+N more` 텍스트 표시
- 날짜 셀 배경색: 현재 월/다른 월 구분만 있음 (위험도 배경 없음)
- 우측 사이드 패널 슬라이드 (FR-02) — 있음
  - 패널 카드: title + status + priority 배지만 표시 (client/project/assignee 없음)
- 하단 이번 달 주문 목록 — 있음

**문제점**:
1. **히트맵 없음**: 납기 건수가 많은 날짜를 시각적으로 구분 불가
2. **위험도 배경 없음**: D-7/overdue 날짜 셀 배경이 일반 날짜와 동일
3. **사이드 패널 정보 부족**: client, project, assignee 미표시
4. **조회 범위 미흡**: 전월 말~다음달 초 그리드 날짜의 주문 누락

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **히트맵 강도 표시**: 납기 건수에 따라 날짜 셀 배경색 진하기 조절 (1건=연한파랑, 4건+=진한파랑) |
| FR-02 | **위험도 배경**: overdue(빨강)/D-7(주황) 주문이 있는 날짜 셀 배경 강조 |
| FR-03 | **사이드 패널 카드 강화**: client, project, assignee, due_badge 추가 |
| FR-04 | **조회 범위 개선**: 캘린더 그리드 첫날~마지막날 범위로 조회 확장 |

### Out of Scope
- 드래그앤드롭 납기일 변경
- 주간/일간 뷰 추가
- 캘린더 인쇄 기능

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/controllers/calendar_controller.rb` | 조회 범위 확장 (그리드 첫날~마지막날) |
| `app/views/calendar/index.html.erb` | 히트맵 CSS + 위험도 배경 + 패널 카드 강화 |

### 3.2 히트맵 강도 로직

```ruby
# 뷰 헬퍼 로직 (ERB 내 인라인)
def heatmap_class(count)
  case count
  when 0    then ''
  when 1    then 'bg-blue-50 dark:bg-blue-900/10'
  when 2..3 then 'bg-blue-100 dark:bg-blue-900/20'
  when 4..6 then 'bg-blue-200 dark:bg-blue-900/30'
  else           'bg-blue-300 dark:bg-blue-900/40'
  end
end
```

### 3.3 위험도 배경 우선순위 (히트맵보다 우선)

```
overdue 주문 있음  → bg-red-50/30 dark:bg-red-900/10
urgent 주문 있음   → bg-orange-50/30 dark:bg-orange-900/10
정상              → 히트맵 색상
```

### 3.4 사이드 패널 카드 구조 개선

```
┌──────────────────────────────────────────┐
│ [주문 제목]                     [D-badge] │
│ client · project                         │
│ [상태 배지]  [우선순위 배지]               │
│ 담당자: 이름                              │
└──────────────────────────────────────────┘
```

패널에 전달하는 JSON에 `client`, `project`, `assignee`, `due_date` 추가

### 3.5 컨트롤러 조회 범위

```ruby
# 그리드 실제 표시 범위
grid_start = @month.beginning_of_month - @month.beginning_of_month.wday.days
grid_end   = grid_start + 41.days  # 6주

@orders = Order.where(due_date: grid_start..grid_end)
               .includes(:assignees, :client, :project)
               .by_due_date
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 납기 건수에 따른 히트맵 배경색 (4단계) 적용 |
| 2 | overdue/D-7 날짜 셀 위험도 배경색 우선 적용 |
| 3 | 사이드 패널 카드에 client, project, assignee 표시 |
| 4 | 컨트롤러 조회 범위가 그리드 첫날~마지막날로 확장 |
| 5 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `Order.by_due_date` scope — 기존 존재
- `order_path(order)` — 기존 존재
- `openOrderDrawer()` JavaScript 함수 — layout에 기존 존재

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
