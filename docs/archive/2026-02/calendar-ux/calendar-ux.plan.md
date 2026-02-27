# Plan: calendar-ux

## 개요

캘린더 UX 개선 — 납기일 클릭 드로어 + 월별 통계 바 + 사이드패널 추가

## 실측 현황 (2026-02-28)

### 이미 구현된 항목
- 월별 그리드 캘린더 (7열, 날짜별 order 표시) ✅
- 이전/다음 월 네비게이션 ✅
- 날짜 셀 내 order 카드 (우선순위 색상, 제목 truncate) ✅
- +N more 표시 (3건 초과 시) ✅
- 하단 이번 달 마감 주문 목록 ✅
- `includes(:assignees)` 쿼리 ✅

### 누락 항목
- 날짜 셀 클릭 → 해당 날 주문 사이드 패널 표시 ❌
- 월별 납기 통계 요약 바 (총건수/지연/긴급/정상) ❌
- 캘린더 카드 클릭 → 기존 Order 드로어 연동 ❌
- 오늘로 이동 버튼 ❌
- 하단 목록에 우선순위 배지 + 납기 D-day 배지 누락 ❌

### 컨트롤러 현황
```ruby
@orders = Order.where(due_date: @month..@month.end_of_month)
               .includes(:assignees)
               .by_due_date
```
- `client`, `project` 미포함 → includes 보강 필요

---

## 기능 요구사항

### FR-01: 월별 납기 통계 바
- 헤더 영역 하단에 4개 숫자 카드:
  - **총 마감** — 해당 월 전체
  - **지연** — due_date < today (빨강)
  - **D-7 이내** — 0 ≤ days ≤ 7 (주황)
  - **정상** — days > 7 (초록)
- 서버 사이드 카운트 (컨트롤러 인스턴스 변수 추가)

### FR-02: 날짜 클릭 → 사이드 패널
- 날짜 셀 클릭 → 우측 슬라이드인 패널
- 패널 내용: 해당 날짜 주문 목록
  - 제목, 상태 배지, 우선순위 배지, 담당자 아바타
  - 각 항목 클릭 → 기존 `openOrderDrawer()` 호출
- 빈 날짜 클릭 시 패널 숨김 또는 "마감 주문 없음" 표시
- Escape 키 / 외부 클릭으로 닫기

### FR-03: 캘린더 카드 → Order 드로어 연동
- 날짜 셀 내 order 카드 클릭 → `openOrderDrawer(id, title, path)` 호출
- 기존 `link_to order_path` 대신 onclick 방식으로 변경

### FR-04: 오늘로 이동 버튼
- 헤더 네비게이션 영역에 "오늘" 버튼 추가
- `calendar_path` (month 파라미터 없음) → 오늘 달로 이동

### FR-05: 하단 목록 배지 강화
- 기존 status 배지 유지
- **우선순위 배지** 추가 (priority_badge helper)
- **D-day 배지** 추가 (due_badge helper)
- client/project 이름 표시 (있을 경우)

---

## 기술 구현 계획

### 컨트롤러 변경
```ruby
# app/controllers/calendar_controller.rb
def index
  @month = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
  @orders = Order.where(due_date: @month..@month.end_of_month)
                 .includes(:assignees, :client, :project)
                 .by_due_date

  # FR-01 통계
  today = Date.today
  @stats = {
    total:   @orders.count,
    overdue: @orders.count { |o| o.due_date < today },
    urgent:  @orders.count { |o| o.due_date >= today && o.due_date <= today + 7 },
    normal:  @orders.count { |o| o.due_date > today + 7 }
  }
end
```

### 뷰 변경
| 파일 | 변경 | 내용 |
|------|------|------|
| `app/controllers/calendar_controller.rb` | 수정 | includes 보강 + @stats |
| `app/views/calendar/index.html.erb` | 수정 | FR-01~05 전체 |

### FR-02 사이드 패널 JS 설계
```javascript
// 날짜 셀 클릭
document.querySelectorAll('[data-calendar-date]').forEach(function(cell) {
  cell.addEventListener('click', function() {
    const date = cell.dataset.calendarDate;
    const orders = JSON.parse(cell.dataset.orders || '[]');
    showDatePanel(date, orders);
  });
});

function showDatePanel(date, orders) {
  // 패널 표시/갱신
}

// Escape / 외부 클릭
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') hideDatePanel();
});
document.getElementById('calendar-panel-overlay').addEventListener('click', hideDatePanel);
```

- 날짜 셀 `<div>`에 `data-calendar-date`, `data-orders` (JSON) 속성 추가
- 패널은 fixed right-side div (z-50, transition)

---

## 영향 범위

| 파일 | 변경 유형 | 내용 |
|------|-----------|------|
| `app/controllers/calendar_controller.rb` | 수정 | includes 보강 + @stats 추가 |
| `app/views/calendar/index.html.erb` | 수정 | FR-01~05 전체 추가 |

## 완료 기준

- [ ] 통계 바 4개 카드 표시 (총/지연/긴급/정상)
- [ ] 날짜 클릭 → 우측 사이드 패널 표시
- [ ] 패널 내 order 클릭 → openOrderDrawer 실행
- [ ] 캘린더 카드 클릭 → openOrderDrawer 실행
- [ ] "오늘" 버튼 동작
- [ ] 하단 목록 배지 (우선순위 + D-day) 표시
- [ ] Gap Analysis Match Rate ≥ 90%
