# Feature Plan: transaction-tracker

**Feature Name**: 거래내역 추적 강화 (Transaction Tracker)
**Created**: 2026-02-25
**Phase**: Plan
**Priority**: HIGH

---

## 개요

CPOFlow의 핵심 요구사항인 "발주처/거래처/현장/담당자별 거래내역 추적"을 강화한다.
Order 테이블에 `client_id`, `supplier_id`, `project_id`, `user_id` FK가 이미 존재하지만,
각 엔티티 상세 페이지의 거래이력 탭이 단순 목록에 불과하여 분석·통계 기능이 없음.

---

## 현재 상태 (AS-IS)

### Client show → 거래이력 탭
- 단순 목록: 제목 + 납기일 + 금액 + 상태
- 필터/정렬 없음
- 통계 없음 (KPI 4개만: 총오더수, 총금액, 활성오더, 프로젝트수)

### Supplier show → 납품 이력 탭
- 단순 목록: 제목 + 금액 + 상태
- 필터/정렬 없음

### Project show → 관련 오더 탭
- 단순 목록: 제목 + 납기 + 금액 + 상태
- 예산 집행률 바 있음 (기초 구현)

### Orders index
- 전체 오더 목록 (테이블)
- 필터: status만 존재 (client/supplier/project/담당자 필터 없음)

---

## 목표 (TO-BE)

### FR-01: 통합 거래내역 필터 (Orders index 강화)
- **발주처(Client)** / **거래처(Supplier)** / **현장(Project)** / **담당자(User)** 필터 추가
- **기간 필터**: 이번달 / 최근 3개월 / 올해 / 직접입력
- **상태 필터**: 기존 유지
- 필터 조합 가능 (AND 조건)
- URL 파라미터로 공유 가능

### FR-02: Client 상세 — 거래이력 탭 강화
- **요약 통계 바**: 상태별 오더 수 (Inbox/Reviewing/Quoted/Confirmed/Procuring/QA/Delivered)
- **기간 필터**: 이번달 / 3개월 / 올해
- **정렬**: 납기일순 / 금액순 / 최신순
- **납기 준수율**: 납기일 기준 on-time vs overdue 비율 표시
- 거래이력 탭에 납기일 색상 코딩 (D-7 빨강 / D-14 주황 / 정상 초록)

### FR-03: Supplier 상세 — 납품 이력 탭 강화
- **요약 통계**: 상태별 분포, 평균 납기일
- **기간 필터**
- **납품 현황 KPI 추가**: 진행중 오더수, 납기 준수율

### FR-04: Project 상세 — 관련 오더 탭 강화
- **상태별 오더 수 뱃지** (칸반 컬럼별)
- **기간 필터**
- **예산 집행 상세**: 오더별 금액 비중 표시

### FR-05: 담당자별 거래내역 (Team 페이지)
- `/team` → 각 팀원 카드에 "담당 오더 N건" 표시
- 팀원 클릭 시 해당 담당자 오더 목록 (orders?user_id=X)

### FR-06: 거래내역 요약 대시보드 위젯 (Dashboard 강화)
- 발주처 Top 5 (거래금액 기준)
- 거래처 Top 5 (공급금액 기준)
- 현장별 오더 집계 (진행중)

---

## 기술 결정

| 항목 | 결정 | 이유 |
|------|------|------|
| 필터 방식 | URL params + scope chain | 북마크/공유 가능, Rails 관례 |
| 통계 계산 | DB 집계 쿼리 (group_by) | N+1 방지 |
| 기간 필터 | created_at 또는 due_date 선택 | 맥락에 따라 |
| 페이지네이션 | kaminari (기존 활용) | 이미 설치됨 |
| 차트 | CSS 기반 바 차트 | 외부 라이브러리 불필요 |

---

## 범위 (이번 사이클)

**포함** (우선순위 HIGH)
- FR-01: Orders index 필터 강화
- FR-02: Client 거래이력 탭 강화
- FR-03: Supplier 납품이력 탭 강화
- FR-04: Project 오더 탭 강화
- FR-06: Dashboard Top 5 위젯

**다음 사이클**
- FR-05: Team 페이지 담당자별 통계

---

## 연관 파일

| 파일 | 변경 유형 |
|------|---------|
| `app/controllers/orders_controller.rb` | 필터 파라미터 처리 |
| `app/views/orders/index.html.erb` | 필터 UI 추가 |
| `app/controllers/clients_controller.rb` | show 액션 쿼리 강화 |
| `app/views/clients/show.html.erb` | 거래이력 탭 재작성 |
| `app/controllers/suppliers_controller.rb` | show 액션 쿼리 강화 |
| `app/views/suppliers/show.html.erb` | 납품이력 탭 재작성 |
| `app/controllers/projects_controller.rb` | show 액션 쿼리 강화 |
| `app/views/projects/show.html.erb` | 오더 탭 재작성 |
| `app/views/dashboard/index.html.erb` | Top 5 위젯 추가 |
| `app/models/order.rb` | 필터 scope 추가 |
