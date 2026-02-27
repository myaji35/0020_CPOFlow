# Plan: dashboard-kpi

## 개요

대시보드 KPI 강화 — 담당자별 워크로드 위젯 추가

## 실측 현황 (2026-02-28)

### 이미 구현된 항목
- KPI 카드 6개 (진행 중, 이번달 납품, 지연 발주, 긴급 D-7, 납기준수율, 이번달 수주액)
- 발주 파이프라인 바 차트 (칸반 단계별)
- 현장 카테고리별 수주 현황 (원전/수력/터널/GTX)
- 기간별 트렌드 차트 (주간/월간/분기/연간 전환)
- 긴급 납기 발주 목록 (Top 5)
- 비자 만료 임박 목록 (90일 이내)
- 계약 만료 임박 목록 (30일 이내)
- Google Sheets 동기화 상태
- **Top5 발주처 위젯** (ROW 5, L460~495) — 컨트롤러 `@top_clients` 완비, 뷰 완성 ✅
- **Top5 거래처 위젯** (ROW 5, L497~531) — 컨트롤러 `@top_suppliers` 완비, 뷰 완성 ✅

### 누락 항목
- **담당자별 워크로드 위젯**: 컨트롤러 `@assignee_workload` 없음, 뷰 없음 ❌

## 기능 요구사항

### FR-01: 담당자별 워크로드 위젯 (신규)
- **컨트롤러**: `@assignee_workload` — User별 활성 Order 수 집계
- **뷰**: ROW 5 하단에 새 ROW 추가 (전체 너비)
- **표시 항목**:
  - 담당자 이름 + 역할 배지
  - 담당 발주 건수 (활성, 긴급, 지연 분류)
  - 비율 바 (최대값 대비 퍼센트)
  - 담당자 발주 목록 링크

### FR-02: 워크로드 정렬 및 필터
- 기본 정렬: 총 담당 건수 내림차순
- 지연 발주가 있는 담당자는 빨간 하이라이트
- 긴급 발주(D-7)가 있으면 주황 카운터 표시

## 기술 구현 계획

### 컨트롤러 변경 (`dashboard_controller.rb`)
```ruby
# 담당자별 워크로드
@assignee_workload = User.joins(:assigned_orders)
                         .where(orders: { status: Order.active_statuses })
                         .select("users.id, users.name, users.role,
                                  COUNT(orders.id) AS total_count,
                                  SUM(CASE WHEN orders.due_date < date('now') THEN 1 ELSE 0 END) AS overdue_count,
                                  SUM(CASE WHEN orders.due_date BETWEEN date('now') AND date('now', '+7 days') THEN 1 ELSE 0 END) AS urgent_count")
                         .group("users.id, users.name, users.role")
                         .order(Arel.sql("total_count DESC"))
                         .limit(10)
```

### 뷰 변경 (`dashboard/index.html.erb`)
- 현재 ROW 5 (`@top_clients`/`@top_suppliers`) 이후에 ROW 6 추가
- 담당자별 워크로드 카드 (전체 너비 또는 2컬럼 그리드)

## 영향 범위

| 파일 | 변경 유형 | 내용 |
|------|-----------|------|
| `app/controllers/dashboard_controller.rb` | 수정 | `@assignee_workload` 쿼리 추가 |
| `app/views/dashboard/index.html.erb` | 수정 | ROW 6 담당자 워크로드 위젯 추가 |

## 전제 조건 확인

- `Order` ↔ `User` 다대다 관계 (`assigned_orders` / `assignments`) 존재 여부 확인 필요
- `Order.active_statuses` 스코프 또는 대체 조건 확인 필요

## 우선순위 및 범위

- **범위**: 소형 기능 (2개 파일 변경)
- **우선순위**: High — 대표님이 직접 요청
- **예상 복잡도**: Low ~ Medium (관계 모델 확인 후)

## 완료 기준

- [ ] 대시보드에 담당자별 워크로드 위젯이 표시됨
- [ ] 각 담당자의 활성/긴급/지연 발주 건수가 정확히 집계됨
- [ ] 지연 담당자 하이라이트 표시 동작
- [ ] Gap Analysis Match Rate ≥ 90%
