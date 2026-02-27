# Plan: team-ux

## 개요

팀 현황 UX 강화 — 워크로드 히트맵 + 상태 분포 차트 + 업무 타임라인 + 과부하 경고

## 실측 현황 (2026-02-28)

### 이미 구현된 항목
- 팀원 카드 그리드 (이름/역할/지사) ✅
- 진행 중 주문 수 + 대기 태스크 수 ✅
- 워크로드 바 (active_orders × 10%) ✅
- 팀원 상세 페이지 (상태별 배지 + 진행 중 주문 목록) ✅

### 누락 항목
- 팀 전체 요약 통계 바 (총원/총 진행/지연/과부하) ❌
- 워크로드 히트맵 (팀원별 우선순위별 주문 분포) ❌
- 과부하 경고 배지 (active ≥ 8건) ❌
- 팀원 상세 — 납기 D-day 배지 + priority_badge + 드로어 연동 ❌
- 팀원 상세 — 지연 주문 별도 섹션 ❌

### 컨트롤러 현황
```ruby
# index: active_orders + tasks_pending 만 계산
# show: active_orders (limit 10) + status_counts 만
```
- overdue, urgent 카운트 없음
- `includes` 미흡 (N+1 가능성)

---

## 기능 요구사항

### FR-01: 팀 전체 요약 통계 바
- 헤더 하단 4개 카드:
  - **총 팀원** — members.count
  - **총 진행 주문** — 전체 active_orders 합계
  - **지연 주문** — due_date < today (빨강)
  - **과부하 팀원** — active ≥ 8명 수 (주황)

### FR-02: 워크로드 카드 강화
- 기존 2개 숫자 카드(진행/태스크) 유지
- 지연(overdue) + 긴급(urgent, D-7) 카운트 추가
- **과부하 경고 배지** — active ≥ 8건이면 카드 우상단에 "과부하" 빨간 배지
- 워크로드 바 색상 기준 개선:
  - 0~4건 → 초록, 5~7건 → 주황, 8건+ → 빨강

### FR-03: 팀원 상세 (show) 강화
- **지연 주문 섹션** 별도 분리 (due_date < today)
- 진행 중 주문 목록:
  - `priority_badge` + `due_badge` 추가
  - `link_to "보기"` → `onclick openOrderDrawer()` 로 변경
  - client/project 이름 표시
- limit(10) → limit(20) 확장

---

## 기술 구현 계획

### 컨트롤러 변경

```ruby
# index
@workloads = @members.map do |u|
  today  = Date.today
  active = u.assigned_orders.active
  {
    user:           u,
    active_orders:  active.count,
    tasks_pending:  u.tasks.pending.count,
    overdue_orders: active.count { |o| o.due_date && o.due_date < today },
    urgent_orders:  active.count { |o| o.due_date && o.due_date >= today && o.due_date <= today + 7 }
  }
end

# @summary (FR-01)
@summary = {
  total_members:   @members.count,
  total_active:    @workloads.sum { |w| w[:active_orders] },
  total_overdue:   @workloads.sum { |w| w[:overdue_orders] },
  overloaded:      @workloads.count { |w| w[:active_orders] >= 8 }
}

# show
@overdue_orders = @member.assigned_orders.overdue.by_due_date
@active_orders  = @member.assigned_orders.active
                          .where("due_date >= ? OR due_date IS NULL", Date.today)
                          .by_due_date.limit(20)
                          .includes(:client, :project)
```

### 뷰 변경
| 파일 | 변경 | 내용 |
|------|------|------|
| `app/controllers/team_controller.rb` | 수정 | overdue/urgent 카운트 + @summary + show 강화 |
| `app/views/team/index.html.erb` | 수정 | FR-01 통계 바 + FR-02 카드 강화 |
| `app/views/team/show.html.erb` | 수정 | FR-03 지연 섹션 + 배지 + 드로어 연동 |

---

## 영향 범위

| 파일 | 변경 유형 |
|------|-----------|
| `app/controllers/team_controller.rb` | 수정 |
| `app/views/team/index.html.erb` | 수정 |
| `app/views/team/show.html.erb` | 수정 |

## 완료 기준

- [ ] 팀 전체 통계 바 4개 카드 표시
- [ ] 팀원 카드에 지연/긴급 카운트 표시
- [ ] active ≥ 8건 → "과부하" 배지 + 카드 테두리 강조
- [ ] 팀원 상세 — 지연 주문 별도 섹션
- [ ] 팀원 상세 — priority_badge + due_badge + 드로어 연동
- [ ] Gap Analysis Match Rate ≥ 90%
