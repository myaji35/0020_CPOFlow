# Domain Analysis — CPOFlow — 2026-04-22

## Entities (13개)

| 엔티티 | 핵심 필드 | 비고 |
|---|---|---|
| Order | status(9단계), rfq_status(4단계), currency, due_date, ecount_slip_no, parent_order_id | 핵심 집계 단위 |
| User | role(4단계), branch(2개), locale, notification_preferences | 인증·권한의 주체 |
| Client | name, code(unique), industry, credit_grade, payment_terms, currency | 발주처 |
| Supplier | name, products, payment_terms | 거래처 |
| Project | client FK, status(4단계), budget, site_category | Client 소속, 예산 관리 |
| Employee | user FK(optional), nationality, employment_type, visa, certifications | HR 주체 |
| KanbanBoard | board_type(purchase/sales/project/custom), is_default, owner_id | 보드 컨테이너 |
| KanbanColumn | kanban_board FK, key, wip_limit | 커스텀 보드 컬럼 |
| CardStatus | key(unique), auto_rule JSON, is_default, position | 카드 시각 분류 |
| OrderLink | source/target(polymorphic), relation(5종), status(3종), confidence | 온톨로지 엣지 |
| OrderQuote | order FK, currency | 견적서 |
| RfqFeedback | order FK, user FK, verdict(confirmed/rejected/reverted), ai_score | AI 학습 피드백 |
| MenuPermission | role × menu_key, can_read/create/update/delete | 권한 매트릭스 |

---

## Rules (23개)

### Critical (P0) — 위반 시 데이터 정합성 또는 보안 파괴

**R01. 칸반 new_rfq 게이트**
new_rfq 컬럼은 rfq_status=rfq_triage 카드만 표시. rfq_pending/rfq_excluded/rfq_archived는 인박스 전용.
근거: `Order::KANBAN_VISIBLE_RFQ_STATUSES = %i[rfq_triage]`

**R02. 브랜치 격리**
admin 외 사용자는 자신의 branch(abu_dhabi|seoul) 소속 Order만 조회·수정 가능.
근거: `scoped_orders` — `joins(:user).where(users: { branch: current_user.branch })`

**R03. eCount 전표 자동생성 1회 보장**
status가 new_po로 변경될 때 ecount_slip_no가 없는 경우에만 EcountSlipCreateJob 실행. 중복 방지.
근거: `enqueue_ecount_slip` — `return if ecount_slip_no.present?`

**R04. rfq_excluded/rfq_archived는 칸반 진입 차단**
rfq_convertible? 메서드가 false면 워크플로우 진입 불가.
근거: `rfq_convertible?` — `%w[rfq_triage rfq_pending].include?`

**R05. 첨부 파일 최대 25MB**
MAX_FILE_SIZE = 25.megabytes. 초과 시 업로드 차단.
근거: `OrdersController::MAX_FILE_SIZE`

**R06. CardStatus 삭제 제한**
orders가 1건 이상 연결된 CardStatus는 `restrict_with_error`로 삭제 불가.
근거: `has_many :orders, dependent: :restrict_with_error`

### Major (P1) — 기능 이상 또는 UX 파괴 가능

**R07. Order 생성자 강제 지정**
수동 생성 Order는 `current_user`를 creator(user FK)로 강제 설정. 빈 creator 불가.
근거: `@order.user = current_user`

**R08. Order 신규 생성 시 status 강제 = new_rfq, rfq_status = rfq_triage**
수동 생성 카드는 항상 new_rfq 컬럼 + rfq_triage 상태로 시작.
근거: `create` 액션 `@order.status = :new_rfq; @order.rfq_status = :rfq_triage`

**R09. Order.title, customer_name, status 필수값**
3개 중 하나라도 없으면 저장 불가.
근거: `validates :title, :customer_name, :status, presence: true`

**R10. Client.code 유일**
같은 code의 Client 중복 불가.
근거: `validates :code, uniqueness: true`

**R11. 삭제 권한은 manager 이상**
Client, Project, Employee 삭제는 manager+ 전용. viewer/member는 삭제 불가.
근거: `before_action :require_manager!, only: %i[destroy]`

**R12. 관리자 메뉴(admin 라우트)는 admin 전용**
reviews, sheets_config, kanban 보드 설정, API 키 설정 = admin only.
근거: `before_action :require_admin!`

**R13. eCount 중복 전표 제거**
ecount_sync_controller에서 관리자 이상(require_manager!)만 동기화 실행 가능.

**R14. 칸반 drag-drop 상태전이 audit 기록**
move 액션 시 from_status/to_status를 Activity로 기록. 감사 추적 필수.
근거: `Activity.create!(action: "status_changed", from_status:, to_status:)`

**R15. CardStatus 자동 배정 규칙**
due_date 변경 시 CardStatus::AutoAssigner 호출. 단, card_status_manually_set_at이 설정된 경우 자동 배정 스킵.
근거: `should_auto_reassign?` — `card_status_manually_set_at.blank?`

**R16. AI Rate Limit**
사용자당 분당 10회 이하 AI API 호출(translate/analyze_link/generate_reply).
근거: `RATE_LIMIT_WINDOW=60, RATE_LIMIT_MAX=10`

**R17. 병합 대상은 독립 카드(parent_order_id nil)만 가능**
이미 sub_order인 카드는 병합 대상에서 제외.
근거: `next if order.parent_order_id.present?`

**R18. Gmail 스레드 연관 카드 상태 동기화**
동일 gmail_thread_id의 new_rfq 카드는 status 변경 시 자동으로 같이 변경.
근거: `sync_thread_siblings_status`

### Minor (P2) — 품질·UX 영향

**R19. OrderLink confidence 범위 0.0~1.0**
관계 신뢰도는 부동소수점 0~1로 제한.
근거: `validates :confidence, numericality: { in: 0.0..1.0 }`

**R20. CardStatus key 포맷 제한**
소문자+숫자+언더스코어만 허용, uniqueness 보장.
근거: `format: { with: /\A[a-z0-9_]+\z/ }`

**R21. 저장 필터 최대 10개**
User.saved_filters_for("orders") 최대 10개 유지.
근거: `list.last(10)`

**R22. 감사 필드 자동 기록**
estimated_value, quantity, currency, due_date, supplier_id, client_id, project_id, po_no, rfq_no, quo_no, payment_terms, delivery_location, item_name, title 변경 시 Activity 기록.
근거: `AUDITED_FIELDS`

**R23. Project는 반드시 Client 소속**
Project.client 필수(presence: true). orphan project 불가.
근거: `validates :name, :client, presence: true`

---

## Scenarios (역할별 12개)

### admin (3개)

**A-1. 정상: 전체 보드 관리 + eCount 동기화**
1. 로그인 → 칸반 진입 (전 브랜치 Order 조회)
2. Settings > Kanban Boards에서 신규 보드 생성 (board_type: "purchase")
3. Admin > eCount Sync 실행 → 동기화 로그 확인
4. Admin > Reviews에서 API 키 유효성 검토
- 기대: 전 브랜치 데이터 접근, eCount 전표 생성, 보드 CRUD 완료

**A-2. 엣지: 브랜치 간 중복 reference_no 처리**
1. abu_dhabi 브랜치 Order와 seoul 브랜치 Order가 동일 reference_no 보유
2. admin이 칸반에서 둘 다 조회 가능(branch 격리 없음)
3. 병합 시도 → 같은 reference_no 그룹으로 인식
- 기대: 두 Order 모두 보임, 병합 가능, 의도치 않은 크로스브랜치 병합 위험 존재

**A-3. 실패: CardStatus 삭제 시도 (Order 연결됨)**
1. Settings > CardStatuses에서 "urgent" 삭제 시도
2. urgent CardStatus에 Order 1건 이상 연결됨
3. restrict_with_error 발동 → 삭제 실패
- 기대: 422 Unprocessable Entity + 에러 메시지 표시

### manager (3개)

**M-1. 정상: 신규 RFQ 수신 → 칸반 이동 → eCount 전표**
1. 인박스에서 rfq_pending Order 확인
2. AI 판정 후 rfq_triage로 변경 → 칸반 new_rfq 컬럼에 노출
3. make_quo → pending_po → new_po로 drag-drop 이동
4. new_po 전환 시 ecount_slip_no 자동 발급 확인
- 기대: 각 단계 Activity 기록, eCount 전표 1회만 생성

**M-2. 엣지: 마감일 초과 + 담당자 미배정 = critical 스코프**
1. 마감일 경과 Order에 카드 상태 "urgent", 담당자 배정 없음
2. critical scope 조회 → 해당 Order 포함 확인
3. manager가 담당자 배정
- 기대: critical? == true 해소, CardStatus 자동 재배정(overdue 해제 조건 충족 시)

**M-3. 실패: member가 Client 삭제 시도**
1. member role 유저가 ClientsController#destroy 호출
2. require_manager! 발동 → redirect root_path + alert
- 기대: 403-equivalent redirect, 삭제 미실행

### member (3개)

**B-1. 정상: Order 생성 → 첨부파일 업로드 → 코멘트**
1. 칸반 "+" 버튼 → 신규 Order 폼 (status: new_rfq, rfq_status: rfq_triage 자동 설정)
2. 파일 첨부 (25MB 이하 PDF)
3. 코멘트 작성 → Activity 기록 확인
- 기대: Order 저장 성공, 첨부 완료, creator = current_user

**B-2. 엣지: 다른 브랜치 Order 접근 시도**
1. seoul 브랜치 member가 abu_dhabi Order URL 직접 입력
2. scoped_orders 브랜치 격리로 조회 불가
- 기대: 404 또는 redirect (set_order에서 Order.find가 브랜치 격리 미적용으로 실제로는 접근 가능 — GAP)

**B-3. 정상: URL 첨부 (Google Drive 링크)**
1. Order 드로어 > 첨부 탭 > URL 입력
2. Google Drive 파일 URL → 자동 다운로드 시도
3. 다운로드 실패 시 링크로 fallback 저장
- 기대: 파일 첨부 또는 extracted_links에 URL 저장, Activity 기록

### viewer (3개)

**V-1. 정상: 읽기 전용 조회**
1. 로그인 → 칸반 조회 (can_read?(:kanban) == true)
2. Order 상세 드로어 열기 → 댓글/첨부파일 열람
3. 수정 버튼 없음 확인
- 기대: CRUD 버튼 미표시, GET 요청만 허용

**V-2. 엣지: viewer가 Order 생성 API 직접 호출**
1. viewer가 POST /orders 직접 요청
2. MenuPermission.can_create?(:kanban) == false
- 기대: 실제로 OrdersController에 can_create? 가드 없음 — viewer도 Order 생성 가능 (GAP)

**V-3. 실패: viewer가 AI 번역/분석 요청**
1. viewer가 Inbox > 번역 버튼 클릭
2. Rate limit 체크 통과 (10회 이하) — 역할 체크 없음
- 기대: 역할 기반 AI 호출 제한 없음 — 모든 로그인 유저가 AI 사용 가능 (GAP)

---

## Missing Rules (Critical Gap 5개)

**CRITICAL-1. Order 상세 접근 시 브랜치 격리 미적용**
`set_order`에서 `Order.find(params[:id])` 직접 호출 — `scoped_orders`를 사용하지 않음.
다른 브랜치 Order의 show/edit/update/destroy URL 직접 입력 시 접근 가능.
권고: `@order = scoped_orders.find(params[:id])`로 변경.

**CRITICAL-2. viewer 역할의 Order 생성/수정 차단 미구현**
`OrdersController`에 `can_create?` / `can_update?` before_action 가드 없음.
MenuPermission에 viewer=can_create:false 정의되어 있으나 컨트롤러에서 강제화하지 않음.
권고: `before_action -> { require_permission!(:kanban, :create) }, only: %i[new create]`

**CRITICAL-3. Order 삭제 권한 가드 없음**
`OrdersController#destroy`에 role 체크 없음. viewer/member 포함 모든 로그인 유저가 삭제 가능.
권고: `before_action :require_manager!, only: %i[destroy]`

**MAJOR-1. AI 호출 역할 제한 없음**
`InboxController`의 translate/analyze_link/generate_reply는 rate limit만 있고 role 체크 없음.
viewer도 AI API를 분당 10회 호출 가능 → 비용 무한정 발생 가능.
권고: `before_action -> { require_member! }, only: %i[translate analyze_link generate_reply]`

**MAJOR-2. give_up → done 전환 후 재활성화 경로 미정의**
give_up(7), done(8) 상태에서 active 상태(1~6)로 되돌아가는 규칙이 없음.
칸반 drag-drop이 any→any를 허용하므로 done 카드를 new_rfq로 되돌릴 수 있으나
ecount_slip_no가 이미 발급된 상태에서 new_po로 재진입 시 중복 전표 발생 가능성 있음.
권고: ecount_slip_no 존재 시 new_po 재진입 차단 검증 추가.
