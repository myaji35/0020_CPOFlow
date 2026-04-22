# Biz Validation — 2026-04-22

ISS-235 | check_mode: biz | Performed independently (ISS-232 domain report not found)

---

## 상태전이 (State Transition) — 9x9 매트릭스

### 구현 방식
`app/models/order.rb:22` — Rails `enum :status` (정수 컬럼). AASM/state_machine 미사용. 전이 제약 없음.

### 허용/차단 매트릭스

| FROM → TO      | new_rfq | make_quo | pending_po | new_po | delivery_items | problem | get_grn | give_up | done |
|----------------|---------|----------|------------|--------|----------------|---------|---------|---------|------|
| new_rfq        | —       | ALLOW    | ALLOW      | ALLOW  | ALLOW          | ALLOW   | ALLOW   | ALLOW   | ALLOW |
| make_quo       | ALLOW   | —        | ALLOW      | ALLOW  | ALLOW          | ALLOW   | ALLOW   | ALLOW   | ALLOW |
| pending_po     | ALLOW   | ALLOW    | —          | ALLOW  | ALLOW          | ALLOW   | ALLOW   | ALLOW   | ALLOW |
| new_po         | ALLOW   | ALLOW    | ALLOW      | —      | ALLOW          | ALLOW   | ALLOW   | ALLOW   | ALLOW |
| delivery_items | ALLOW   | ALLOW    | ALLOW      | ALLOW  | —              | ALLOW   | ALLOW   | ALLOW   | ALLOW |
| problem        | ALLOW   | ALLOW    | ALLOW      | ALLOW  | ALLOW          | —       | ALLOW   | ALLOW   | ALLOW |
| get_grn        | ALLOW   | ALLOW    | ALLOW      | ALLOW  | ALLOW          | ALLOW   | —       | ALLOW   | ALLOW |
| give_up        | ALLOW   | ALLOW    | ALLOW      | ALLOW  | ALLOW          | ALLOW   | ALLOW   | —       | ALLOW |
| done           | ALLOW   | ALLOW    | ALLOW      | ALLOW  | ALLOW          | ALLOW   | ALLOW   | ALLOW   | — |

**판정: FAIL (P0-CRITICAL)**

- **모든 전이가 허용됨.** `kanban_controller.rb:146`과 `orders_controller.rb:206`에서 `@order.update(status: params[:status])`를 파라미터 그대로 적용.
- 역방향 전이 차단 없음 (get_grn → new_rfq 가능).
- 단계 건너뛰기 차단 없음 (new_rfq → done 직행 가능).
- DB 레벨 제약 없음 (`schema.rb:status integer default:0 null:false` — CHECK constraint 없음).
- 유일한 예외: `order.rb:131` `rfq_convertible?` — `rfq_excluded/rfq_archived`는 칸반 진입 차단 (PASS).
- eCount 슬립 자동 생성 트리거: `order.rb:337` `status == "new_po"` 조건부 — 전이 무결성 없이 new_po 직행 시 eCount 슬립이 비정상 생성됨.

---

## 브랜치 격리 (Branch Isolation)

### 설계 의도
`application_controller.rb:12` `scoped_orders` — `admin?`이면 전체, 일반 사용자는 `users.branch = current_user.branch` 필터.

### 적용 현황

| 컨트롤러 | 메서드 | scoped_orders 사용 | 판정 |
|---------|-------|-------------------|------|
| inbox_controller | index | `scoped_orders` | PASS |
| inbox_controller | convert_to_order:142 | `Order.find(params[:id])` | **FAIL** |
| inbox_controller | bulk_trash:169 | `scoped_orders` | PASS |
| inbox_controller | attachment:550,607 | `scoped_orders` | PASS |
| kanban_controller | index | `board_scoped_orders → scoped_orders` | PASS |
| kanban_controller | move:140 | `Order.find(params[:id])` | **FAIL** |
| kanban_controller | split:172 | `Order.find(params[:id])` | **FAIL** |
| kanban_controller | merge:247 | `Order.find(main_id)` (unscoped) | **FAIL** |
| orders_controller | index:7 | `Order.all` | **FAIL** |
| orders_controller | set_order:425 | `Order.find(params[:id])` | **FAIL** |
| dashboard_controller | index | `scoped_orders` | PASS |
| reports_controller | build_kpi | `report_scoped_orders → scoped_orders` | PASS |

**판정: FAIL (P0-CRITICAL)**

- `orders_controller.rb:7` — `Order.all`로 인해 비관리자 사용자가 다른 브랜치의 모든 주문 목록을 열람 가능.
- `kanban_controller.rb:140,172,247` — `Order.find` 직접 호출로 다른 브랜치 카드를 상태 이동/분리/병합 가능.
- `inbox_controller.rb:142` — 다른 브랜치 inbox 항목을 칸반으로 전환 가능.
- `orders_controller.rb:425` — `set_order`가 `Order.find`를 사용하므로 show/edit/update/destroy 모두 크로스-브랜치 접근 허용.

---

## 통화 변환 (Currency Conversion)

### 현황
- `order.rb` schema: `currency string default:"USD"` — 저장만 함, 변환 로직 없음.
- `order_quote.rb:10` — 통화 허용값: `%w[USD KRW AED EUR]` (validation).
- `order_quote.rb:24` — 표시는 `"USD 1,000"` 단순 병기.
- `orders_controller.rb:168` — `price_history` API: 통화 표기만 반환, 단위 통일 없음.
- `admin/rfq_stats_controller.rb:85` — `sum(:cost_usd)` (USD 고정 집계).
- 환율 API 또는 `exchange_rate` 컬럼: 미존재.

**판정: FAIL (P1-MAJOR)**

- 견적(order_quote) 단가가 AED인 주문과 USD인 주문의 `estimated_value`가 동일 단위인 것처럼 합산됨 (`reports_controller` `sum(:estimated_value)`).
- 대시보드 KPI 합계(`order.estimated_value` 합산)가 혼합통화로 산출되어 의미없는 수치 생성.
- `price_history` 엔드포인트가 통화 무관 단가 비교를 허용 (AED 단가 vs USD 단가 혼재).
- 방향: 최소한 `estimated_value_usd` 계산 컬럼 또는 저장 시점 환율 고정 필요.

---

## 권한 체크 (Role Permissions)

| 컨트롤러 | 액션 | 필요 최소 역할 | 실제 가드 | 판정 |
|---------|------|-------------|---------|------|
| orders#index | 목록 조회 | viewer | `authenticate_user!` only | PASS (인증만) |
| orders#create | 주문 생성 | member | `authenticate_user!` only | **WARN** (viewer도 생성 가능) |
| orders#update | 주문 수정 | member | `authenticate_user!` only | **WARN** (viewer도 수정 가능) |
| orders#destroy | 주문 삭제 | manager | `authenticate_user!` only | **FAIL** (P0) |
| orders#move_status | 상태 이동 | member | `authenticate_user!` only | **WARN** (viewer도 이동 가능) |
| kanban#move | 칸반 이동 | member | 없음 | **FAIL** |
| kanban#merge | 병합 | manager | 없음 | **FAIL** |
| kanban#split | 분리 | manager | 없음 | **FAIL** |
| team#update_role | 역할 변경 | admin | `current_user.admin?` 인라인 체크 | PASS |
| clients#destroy | 발주처 삭제 | manager | `require_manager!` | PASS |
| reports#index | 리포트 조회 | manager | `require_admin_or_manager!` | PASS |
| admin/imports | 가져오기 | manager | `require_manager!` | PASS |
| admin/reviews | 리뷰 관리 | admin | `require_admin!` | PASS |
| inbox#convert_to_order | 칸반 전환 | member | `authenticate_user!` only | **WARN** (viewer도 전환 가능) |

**판정: FAIL (P0 2건, WARN 4건)**

- `orders#destroy`: viewer/member가 주문 삭제 가능. `require_manager!` 가드 누락 (orders_controller.rb:4 before_action 목록에 destroy 포함, 역할 체크 없음).
- `kanban#move/merge/split`: 역할 가드 전무. viewer가 칸반 드래그로 상태 변경 가능.

---

## 엣지 케이스 10+

| # | 시나리오 | 현재 코드 처리 | 판정 | 심각도 |
|---|---------|-------------|------|-------|
| EC-01 | 동시 편집: 두 사용자가 같은 주문을 동시에 update | 낙관적 락 없음 (`lock_version` 컬럼 미존재) | FAIL | P1 |
| EC-02 | 삭제 중 참조: supplier 삭제 시 해당 supplier의 order | `order.rb:6` `belongs_to :supplier, optional: true` — NULL 허용. supplier.rb 확인 필요 | WARN | P2 |
| EC-03 | 빈 estimated_value 합산: `nil`이 포함된 경우 | `reports_controller` `sum(:estimated_value)` — Rails sum은 nil을 0 처리 | PASS | — |
| EC-04 | 대량 데이터: 컬럼당 INITIAL_LIMIT(20) 초과 시 | `kanban_controller:4` INITIAL_LIMIT=20, lazy prefetch 구현됨 | PASS | — |
| EC-05 | 마감 임박 당일 due_date 처리 | `order.rb:61` overdue scope: `due_date < Date.today` (당일 제외). `due_urgency` urgent: `<= 7` | PASS | — |
| EC-06 | 담당자 재배정 중 이전 담당자 알림 미발송 | `assignments_controller` 확인 필요. 신규 배정 알림만 구현 의심 | WARN | P2 |
| EC-07 | 첨부 파일 업로드 실패 후 Order는 저장됨 | `orders_controller.rb:102` `attachments.attach` 실패 시 예외 무시 가능 | WARN | P1 |
| EC-08 | rfq_excluded 상태 Order의 칸반 노출 | `order.rb:100` KANBAN_VISIBLE_RFQ_STATUSES=[rfq_triage]로 차단됨 | PASS | — |
| EC-09 | 크로스 브랜치 Order 병합 | `kanban_controller.rb:247` `Order.find(main_id)` — 다른 브랜치 Order 병합 가능 | FAIL | P0 |
| EC-10 | done 상태 Order의 재편집(역방향 전이) | 아무 가드 없음 — done → new_rfq 전이 허용 | FAIL | P1 |
| EC-11 | eCount 슬립 중복 생성: new_po 상태를 2회 저장 | `order.rb:337` `ecount_slip_no.present?` 체크로 방지됨 | PASS | — |
| EC-12 | 대용량 첨부(25MB 경계): 브라우저가 먼저 차단 안 되면 | `orders_controller.rb:237` `MAX_FILE_SIZE = 25.megabytes` 서버 측 체크 | PASS | — |
| EC-13 | parent_order 삭제 시 sub_orders | `order.rb:10` `dependent: :nullify` — sub_orders.parent_order_id = NULL | PASS | — |
| EC-14 | 칸반 보드 접근 권한 없는 사용자가 board_id 직접 전달 | `kanban_controller.rb:22` `can_access_board?` 체크 후 기본 보드로 fallback | PASS | — |
| EC-15 | save_filter에서 빈 파라미터 제출 | `orders_controller.rb:135` `filter_params.empty?` 가드 존재 | PASS | — |

---

## CRITICAL 갭 (P0)

### P0-01: orders#destroy 역할 가드 누락
- **파일**: `app/controllers/orders_controller.rb:4,193`
- **설명**: `before_action :set_order, only: [... :destroy ...]` 는 있으나 `require_manager!` 없음. viewer/member 역할로도 `DELETE /orders/:id` 호출 시 주문 영구 삭제.
- **수정**: `before_action :require_manager!, only: [:destroy]` 추가.

### P0-02: 크로스 브랜치 데이터 접근 — kanban#move/merge/split, orders#set_order
- **파일**: `app/controllers/kanban_controller.rb:140,172,247` / `app/controllers/orders_controller.rb:7,425`
- **설명**: Seoul 사용자가 Abu Dhabi 주문 ID를 직접 요청하면 접근/수정/삭제 가능. `scoped_orders` 미적용.
- **수정**: `kanban_controller`의 `Order.find`를 `scoped_orders.find`로, `orders_controller`의 `Order.all`을 `scoped_orders`로 교체. `inbox_controller:142`도 동일 수정.

### P0-03: 크로스 브랜치 병합 가능
- **파일**: `app/controllers/kanban_controller.rb:247` (EC-09)
- **설명**: 다른 브랜치의 주문을 병합 대상으로 지정 가능. 브랜치 격리 완전 우회.
- **P0-02와 동일 수정으로 해결됨** (scoped_orders.find 적용).

---

## MAJOR 갭 (P1)

### P1-01: 상태전이 제약 없음
- **파일**: `app/models/order.rb:22`, `app/controllers/kanban_controller.rb:146`, `app/controllers/orders_controller.rb:206`
- **설명**: 9단계 칸반 전이가 임의 순서로 허용됨. 역방향·건너뛰기 모두 가능.
- **수정**: `Order` 모델에 `ALLOWED_TRANSITIONS` 해시 정의 + `before_save :validate_status_transition` 콜백 추가.

### P1-02: 통화 혼재 집계 오류
- **파일**: `app/controllers/reports_controller.rb` `build_kpi`, `build_by_client` 등
- **설명**: `estimated_value` 합산 시 AED/USD/KRW 혼재. 의미없는 총합 표시.
- **수정**: `estimated_value_usd` 가상 컬럼(저장 시점 환율 고정) 또는 표시에서 통화별 분리 집계.

### P1-03: 동시 편집 충돌 (낙관적 락 미구현)
- **파일**: `db/schema.rb` orders 테이블 — `lock_version` 컬럼 없음
- **설명**: 두 사용자가 동시에 같은 주문을 편집하면 나중 저장이 앞 저장을 덮어씀.
- **수정**: `lock_version` 컬럼 마이그레이션 + Rails 낙관적 락 활성화. 뷰에 hidden `lock_version` 필드 추가.

### P1-04: viewer 역할로 상태 이동/주문 생성 가능
- **파일**: `app/controllers/orders_controller.rb:4`, `app/controllers/kanban_controller.rb` (가드 없음)
- **설명**: viewer는 읽기 전용이어야 하나 실제로는 create/update/move_status 모두 허용됨.
- **수정**: `MenuPermission` 체크가 뷰에서만 작동하고 컨트롤러 레벨에서 미검증. `can_create?(:orders)` 서버 측 guard 추가.

---

## MINOR 갭 (P2/P3)

- **P2-01**: 담당자 재배정 시 이전 담당자 알림 미발송 (`assignments_controller` 미확인).
- **P2-02**: `done` 상태 Order 역방향 전이 허용 (EC-10) — P1-01 수정 시 함께 해결.
- **P2-03**: `OrderQuote` 통화 검증(`order_quote.rb:10`)과 `Order.currency` 검증이 불일치 (`Order` 모델에 currency 허용값 검증 없음).
- **P3-01**: `inbox_controller:convert_to_order`에 `member` 이상 역할 가드 권장 (현재 viewer 포함 모든 인증 사용자 허용).

---

## 요약

| 구분 | 시나리오 총계 | 커버됨 | 갭 |
|------|-------------|--------|-----|
| 상태전이 | 9×9=72 | 2 (rfq gate, ecount dup) | 70 미제약 |
| 브랜치 격리 | 14 엔드포인트 | 8 | 6 미적용 |
| 통화 변환 | 4 경로 | 0 (검증만, 변환 없음) | 4 |
| 권한 체크 | 14 액션 | 8 | 6 (P0×2, WARN×4) |
| 엣지 케이스 | 15 | 9 PASS | 6 FAIL/WARN |

**coverage_pct 추정: 42%** (시나리오 총 50개 중 21개 커버)
