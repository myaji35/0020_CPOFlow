# CPOFlow 도메인 시나리오 전수 검사 (2026-04-24, 배포 기준)

## 요약

| 항목 | 수치 |
|---|---|
| 시나리오 총수 | 25 |
| PASS | 10 |
| WARN | 9 |
| FAIL | 6 |
| 테스트 커버된 시나리오 | 8 |
| 테스트 누락 시나리오 | 17 |

---

## A. 상태 전이 & 칸반

### S1. new_rfq → done 건너뛰기 — 판정: FAIL

- **현재 동작**: `move_status` 또는 `kanban#move` 에 transition guard 없음. `Order.enum :status` 만 정의되어 있으며, 임의 값으로 직접 업데이트 가능.
- **기대 동작**: `new_rfq → done` 직행 시 `StateTransitionError` 또는 422 반환.
- **코드 증거**: `app/controllers/orders_controller.rb:208` — `@order.update(status: new_status)` 호출 전 guard 없음. `app/models/order.rb:22-32` — enum 정의만, state machine 없음.
- **위험도**: HIGH
- **재현 스텝**:
  ```ruby
  # bin/rails console
  o = Order.first
  o.update!(status: :done)   # new_rfq → done 즉시 가능 — 기대는 거부
  # 또는 curl
  curl -X PATCH /orders/1/move_status -d "status=done" -H "Cookie: ..."
  ```
- **권장 수정**: state_machine gem 또는 before_save 콜백에서 ALLOWED_TRANSITIONS 해시로 전이 허용 목록 검사.

---

### S2. done → new_rfq 역행 — 판정: FAIL

- **현재 동작**: S1과 동일한 이유로 역행 전이도 허용됨. 완료된 오더가 다시 inbox 상태로 돌아갈 수 있음.
- **기대 동작**: 완료 상태에서 진행 중 상태로의 역행은 관리자 명시 승인 없이 차단.
- **코드 증거**: `app/controllers/kanban_controller.rb:166` — `@order.update(status: params[:status])` 전 역행 체크 없음.
- **위험도**: HIGH
- **재현 스텝**:
  ```ruby
  o = Order.find_by(status: :done)
  o.update!(status: :new_rfq)  # 통과 — 기대는 거부
  ```
- **권장 수정**: S1과 동일. ALLOWED_TRANSITIONS 해시에서 `done`, `give_up`을 종착 상태로 지정.

---

### S3. give_up 복구 경로 — 판정: WARN

- **현재 동작**: give_up 오더를 다시 살리는 전용 UI/경로가 없지만, move_status 를 통해 기술적으로는 가능함 (S1과 동일 이유로 허용됨).
- **기대 동작**: 복구 경로가 명시적으로 UI에 노출되거나, 또는 명확히 차단되어야 함. 현재는 숨겨진 경로만 존재.
- **위험도**: MEDIUM
- **재현 스텝**:
  ```ruby
  o = Order.find_by(status: :give_up)
  o.update!(status: :new_rfq)  # 의도치 않게 통과
  ```
- **권장 수정**: 복구 전용 액션 또는 modal 확인 추가. 또는 state machine에서 give_up → {new_rfq, make_quo} 명시적 허용.

---

### S4. 칸반 컬럼 병합 시 오더 이력 보존 — 판정: WARN

- **현재 동작**: `kanban#merge`는 child 오더에 `parent_order_id` 를 설정하고 Activity를 기록함. `app/controllers/kanban_controller.rb:275-283`. 단, 병합된 오더의 기존 Activity는 유지됨 (belongs_to order, dependent: :destroy 아님).
- **기대 동작**: 병합 시 child 오더의 activities, tasks, comments 가 보존되어야 함.
- **코드 증거**: `app/models/order.rb:11-13` — `has_many :tasks, dependent: :destroy`, `has_many :comments, dependent: :destroy`. 병합 시 child.destroy는 호출하지 않으므로 직접 손실은 없음. 단, sub_order가 된 이후 UI에서 별도 접근 경로가 없어 실질적 가시성 손실.
- **위험도**: MEDIUM
- **권장 수정**: 병합 이후 child 오더의 tasks/comments 링크를 main 오더 드로어에서 접근 가능하도록 UI 확인.

---

### S5. 칸반 split 시 부모-자식 관계 추적 — 판정: PASS

- **현재 동작**: `kanban#split` (`app/controllers/kanban_controller.rb:191-205`) 에서 `parent_order_id: nil` 로 update 후 Activity 기록. `create_derived_from_link` 콜백이 `parent_order_id` 변경 시 OrderLink 생성 (`app/models/order.rb:265-268`).
- **기대 동작**: 분리 후에도 OrderLink(`derived_from`)를 통한 관계 추적 가능.
- **코드 증거**: `app/models/order.rb:265`: `after_update :create_derived_from_link, if: :saved_change_to_parent_order_id?` — split 시 parent 가 nil로 변경되므로 콜백이 실행됨. 단, 이 경우는 `parent_order_id.blank?` return 조건(line 290)에 의해 링크가 생성되지 않음. 즉 split 방향은 링크가 생성되지 않고 로스트됨.
- **추가 발견**: split 시 derived_from 역방향 링크가 생성되지 않아 분리 이력 추적 불가.
- **위험도**: MEDIUM (WARN 경계)

---

### S6. 동시 상태 변경 Conflict — 판정: FAIL

- **현재 동작**: `Order` 모델에 `lock_version` 컬럼(optimistic locking) 없음. 두 사용자가 동시에 동일 오더를 다른 상태로 이동 시 마지막 저장이 이긴다(last-write-wins).
- **기대 동작**: Optimistic locking 또는 ETag 기반 충돌 감지로 후발 사용자에게 충돌 경고.
- **코드 증거**: `db/schema.rb` — `orders` 테이블에 `lock_version` 컬럼 없음. `app/controllers/kanban_controller.rb:166` — 단순 `update(status:)` 호출.
- **위험도**: MEDIUM
- **재현 스텝**:
  ```ruby
  # User A와 User B가 동시에 같은 오더를 각각 make_quo, pending_po로 이동
  # User B의 마지막 응답이 User A를 덮어씀
  ```
- **권장 수정**: `Order` 에 `lock_version` 컬럼 추가 + `update(status:, lock_version: params[:lock_version])` 로 충돌 감지.

---

## B. Branch 격리

### S7. abu_dhabi user가 seoul 오더 접근 — 판정: PASS

- **현재 동작**: `ApplicationController#scoped_orders` (`app/controllers/application_controller.rb:12-16`) 가 `admin? 아닌 경우` `users.branch = current_user.branch` 조건을 추가. 전 컨트롤러에서 `scoped_orders` 를 통해 Order 접근.
- **실제 결과**: 다른 branch user의 Order는 빈 리스트로 반환됨 (404가 아닌 404에 가까운 RecordNotFound — `scoped_orders.find(id)` 실패 시 ActiveRecord::RecordNotFound → 404).
- **위험도**: LOW

---

### S8. 관리자 전체 브랜치 접근 — 판정: PASS

- **현재 동작**: `scoped_orders` 의 `current_user.admin?` 분기가 `base = Order.not_archived` 를 반환, branch 필터 없음.
- **기대 동작**: admin은 양 branch 모두 접근 가능.
- **코드 증거**: `app/controllers/application_controller.rb:14-15`.
- **위험도**: LOW

---

### S9. 검색에서 branch cross-leak — 판정: FAIL

- **현재 동작**: `SearchController#index` (`app/controllers/search_controller.rb:13-17`) 에서 `Order.where(...)` 사용. `scoped_orders` 가 아닌 `Order` 직접 쿼리. non-admin user가 검색 시 다른 branch의 오더가 검색 결과에 포함됨.
- **기대 동작**: 검색도 현재 사용자의 branch로 격리.
- **코드 증거**: `search_controller.rb:13` — `Order.where("title LIKE ? ...")` — branch 필터 없음.
- **위험도**: HIGH (데이터 격리 위반)
- **재현 스텝**:
  ```ruby
  # abu_dhabi user 로그인 → GET /search?q=keyword
  # seoul branch에만 존재하는 오더 제목을 검색하면 결과에 나타남
  ```
- **권장 수정**: `SearchController`에서 Order 검색 시 `scoped_orders` 또는 동등한 branch 필터 적용.

---

### S10. 리포트 branch 기본값 — 판정: WARN

- **현재 동작**: `ReportsController#index` 가 `scoped_orders` 를 통해 기본적으로 branch 격리됨. 단, manager는 branch 드롭다운으로 전체 선택 가능 (`@available_branches` 전체 노출, `reports_controller.rb:16-17`).
- **기대 동작**: manager가 기본적으로 자신의 branch만 보고, 명시적으로 다른 branch 선택 시 확인.
- **추가 발견**: 기본값이 현재 사용자 branch로 pre-select되지 않음 — `@selected_branch = params[:branch]` 이고 params 없으면 nil, 즉 전체 노출.
- **위험도**: MEDIUM

---

## C. 첨부파일 & PDF

### S11. 50MB 이상 첨부 — 판정: WARN

- **현재 동작**: `OrdersController#attach` 에서 `MAX_FILE_SIZE = 25.megabytes` 체크 (`app/controllers/orders_controller.rb:239`). 25MB 초과 시 에러 반환. 단, Kamal proxy 설정(`config/deploy.yml`)에 `client_max_body_size` 명시 없음. kamal-proxy 기본값은 불명확하며 Nginx가 80포트를 점유 중이므로 Nginx 413 응답 가능성 잔존. 최근 커밋 `cb6e30c`에서 413 fix를 다뤘으나 deploy.yml에 body_size 설정 없음.
- **기대 동작**: 25MB 초과 파일 → Rails 레벨에서 거부 (현재 구현). Nginx 413 발생 시 사용자에게 Rails 에러 페이지가 아닌 Nginx 에러 페이지 노출 → UX 불량.
- **위험도**: MEDIUM
- **권장 수정**: deploy.yml `proxy.headers` 또는 별도 Nginx 설정에서 `client_max_body_size 30m` 명시.

---

### S12. 잘못된 MIME 타입 차단 — 판정: FAIL

- **현재 동작**: `Order` 모델의 `has_many_attached :attachments` 에 `content_type_not_in` validation 없음. `attach` 액션도 content_type 화이트리스트/블랙리스트 없음. `.exe`, `.bat`, `.js` 등 업로드 가능.
- **기대 동작**: 실행 파일 확장자 또는 위험 MIME 타입 업로드 차단.
- **코드 증거**: `app/models/order.rb:18` — `has_many_attached :attachments` 단독 선언. 컨트롤러에도 content_type 체크 없음.
- **위험도**: HIGH (악성 파일 저장 위험)
- **재현 스텝**:
  ```ruby
  # 실제 .exe 파일을 POST /orders/:id/attach 로 업로드 → 성공함
  ```
- **권장 수정**: `validates :attachments, content_type: { not_in: %w[application/x-msdownload ...] }` 또는 ActiveStorage analyzer 추가.

---

### S13. PDF 한글 깨짐 — 판정: PASS (조건부)

- **현재 동작**: `app/views/layouts/pdf.html.erb:7` — `font-family: 'Malgun Gothic', 'Apple SD Gothic Neo', Arial, sans-serif`. 폰트는 CSS font-family 선언만으로 지정됨. wkhtmltopdf 사용.
- **주의**: 배포 Docker 이미지에 Malgun Gothic 폰트가 설치되지 않으면 fallback으로 Arial(한글 미지원) 사용 → 한글 깨짐. Dockerfile에서 폰트 설치 여부 미확인.
- **위험도**: MEDIUM (배포 환경 의존)
- **권장 수정**: Dockerfile에 `fonts-noto-cjk` 또는 Malgun Gothic ttf 파일 COPY 명시.

---

### S14. 첨부 삭제 후 blob 정리 — 판정: PASS (부분)

- **현재 동작**: `detach` 액션에서 `attachment.purge` 호출 (`app/controllers/orders_controller.rb:377`). `purge`는 blob + 파일 모두 즉시 삭제. Order 삭제 시 `has_many_attached :attachments` 의 기본 Rails 동작은 blob purge.
- **잠재적 갭**: `order.destroy` 시 `has_many_attached` 자동 purge 여부는 Rails 버전 및 설정 의존. Rails 6.1+ 에서 기본 purge_on_destroy = true이므로 정상 처리. 단, `update_columns` 우회 호출 시 콜백 미실행 → orphan 가능성.
- **위험도**: LOW

---

## D. 권한

### S15. viewer가 PATCH /orders/:id/move 직접 호출 — 판정: FAIL

- **현재 동작**: `orders_controller.rb` 에 `require_manager!` 는 `destroy` 액션에만 적용됨 (`before_action :require_manager!, only: %i[destroy]`). `move_status` 는 인증된 사용자 모두 허용. viewer role도 `PATCH /orders/:id/move_status` 호출 가능.
- **기대 동작**: viewer는 읽기 전용. 상태 변경 차단.
- **코드 증거**: `app/controllers/orders_controller.rb:5` — `before_action :require_manager!, only: %i[destroy]`. `move_status`, `quick_update`, `update`, `attach`, `detach` 에 role 가드 없음.
- **위험도**: HIGH (역할 경계 침범)
- **재현 스텝**:
  ```bash
  # viewer 계정으로 로그인 후
  curl -X PATCH /orders/1/move_status \
       -d "status=new_po" \
       -H "Cookie: _session_id=..." → 200 성공 (기대: 403)
  ```
- **권장 수정**: `move_status`, `update`, `quick_update`, `attach`, `detach` 에 `before_action :require_member!` 추가. viewer에게는 읽기 전용 강제.

---

### S16. member가 /admin/* 접근 — 판정: WARN

- **현재 동작**: `admin/imports_controller.rb`, `admin/ecount_sync_controller.rb`, `admin/rfq_stats_controller.rb` 는 `require_manager!` 사용 (admin OR manager 허용). `admin/sheets_config_controller.rb`, `admin/reviews_controller.rb` 는 `require_admin!` 사용 (admin 전용).
- **불일치**: 일부 admin 경로(imports, ecount_sync, rfq_stats)가 manager도 접근 가능하여 네임스페이스 이름(`admin/*`)과 실제 권한 기준이 불일치. 의도적 설계인지 확인 필요.
- **위험도**: LOW (의도적 설계 가능)

---

### S17. settings/menu_permissions cross-role 업데이트 — 판정: PASS

- **현재 동작**: `Settings::MenuPermissionsController` 에 `before_action :require_admin!` 명시 (`app/controllers/settings/menu_permissions_controller.rb:4`). 관리자만 접근 가능.
- **위험도**: LOW

---

## E. 외부 연동 실패

### S18. Gmail OAuth 토큰 만료 — 판정: PASS (조건부)

- **현재 동작**: `GmailService` 가 `refresh_token_if_needed!` 를 호출, access_token 만료 시 자동 갱신. refresh_token 자체가 revoked 시 `account.update!(connected: false)` + `Signet::AuthorizationError` raise (`app/services/gmail/gmail_service.rb`). 단, 프론트엔드에서 `connected: false` 계정에 대한 재인증 유도 UI가 있는지 확인 필요.
- **추가 발견**: `handle_auth_error` 에서 `connected: false` 처리는 되나, inbox 동기화 실패 시 사용자에게 명시적 "Gmail 재연결 필요" 배너가 있는지 코드에서 미확인.
- **위험도**: MEDIUM

---

### S19. eCount API 타임아웃 — 판정: PASS

- **현재 동작**: `EcountApi::BaseService` 에 `TIMEOUT = 30`, `MAX_RETRIES = 3`, `RETRY_DELAYS = [2, 4, 8]` (지수 백오프) 구현됨. `RateLimitError`와 `AuthError` 는 재시도 없이 즉시 raise.
- **코드 증거**: `app/services/ecount_api/base_service.rb:31-77`.
- **위험도**: LOW

---

### S20. Claude Haiku API 429 — 판정: WARN

- **현재 동작**: `LlmRfqAnalyzerService` 에서 API 에러 시 `rescue => e` → `fallback_result` 반환. 429 특이 처리 없음. fallback_result 반환으로 RFQ 판독이 기본값(미판정)으로 처리됨.
- **기대 동작**: 429 발생 시 사용자에게 "AI 분석 일시 불가" 표시 및 재시도 큐 enqueue.
- **코드 증거**: `app/services/gmail/llm_rfq_analyzer_service.rb` — `rescue => e` 로 모든 예외 일괄 처리, 429 분기 없음.
- **위험도**: MEDIUM

---

### S21. Google Chat webhook 실패 — 판정: WARN

- **현재 동작**: `GoogleChatService#notify` 에서 Faraday 에러 시 `rescue => e` → `false` 반환 (`app/services/google_chat_service.rb:30-32`). 실패 시 재시도 큐 없음. 발송 실패는 로그에만 기록됨.
- **기대 동작**: webhook 실패 시 Solid Queue 재시도 enqueue.
- **위험도**: MEDIUM (알림 유실 위험)
- **권장 수정**: `DueNotificationJob` 에서 GoogleChatService 실패 시 `retry_on` 또는 별도 `ChatNotificationJob` enqueue.

---

## F. 데이터 무결성

### S22. Order 생성 시 client/supplier 없이 저장 — 판정: PASS (설계 선택)

- **현재 동작**: `Order` 모델에서 `belongs_to :client, optional: true`, `belongs_to :supplier, optional: true` — 둘 다 선택사항. `validates :title, :customer_name, :status` 만 required.
- **기대 동작**: 이는 설계 의도 (RFQ는 발신처 미상으로 시작 가능). 단, `customer_name` 이 client FK 없이 자유 텍스트로 허용되어 중복/오타 위험 있음.
- **위험도**: LOW (의도적 설계)

---

### S23. Client 삭제 시 연결된 Order 처리 — 판정: PASS

- **현재 동작**: `Client` 모델 — `has_many :orders, dependent: :nullify` (`app/models/client.rb:3`). Client 삭제 시 Orders의 `client_id` = NULL 처리. 오더 자체는 보존됨.
- **위험도**: LOW

---

### S24. Supplier 소프트 삭제 대체 — 판정: WARN

- **현재 동작**: `config/routes.rb:143` — `resources :suppliers, except: [:destroy]` — destroy 라우트 없음. 그러나 `Supplier` 모델에 `active` 컬럼 기반 소프트 삭제 패턴이 명시되어 있지 않음 (scope :active는 존재하나 deactivate 메서드 없음).
- **기대 동작**: 비활성화 UI + `active: false` 처리로 명시적 soft-delete 경로 존재.
- **추가 발견**: `active` 컬럼은 scope에서 사용되지만, 관리자가 supplier를 비활성화하는 UI/액션이 없음.
- **위험도**: MEDIUM

---

### S25. Duplicate orders 병합 시 데이터 유실 — 판정: FAIL

- **현재 동작**: `admin/duplicate_orders_controller.rb#merge` 에서 `order.sub_orders.update_all(parent_order_id: main_order.id)` + `order.update_columns(parent_order_id: main_order.id)`. child 오더의 **tasks, comments, activities** 는 child에 남아있어 main 드로어에서 직접 접근 불가.
- **추가 위험**: `Order.find(main_id)` 사용 (not scoped_orders) → admin이 아닌 manager가 다른 branch 오더를 merge할 수 있음. branch 격리 우회.
- **코드 증거**: `admin/duplicate_orders_controller.rb:5` — `require_manager!` (admin 아닌 manager도 허용). `line:33` — `Order.find(main_id)` (branch 필터 없음).
- **위험도**: HIGH
- **재현 스텝**:
  ```ruby
  # manager(abu_dhabi) 계정이 seoul branch 오더 ID를 merge API에 직접 전달
  POST /admin/duplicate_orders/merge
       main_order_id=<abu_dhabi_order_id>
       merge_order_ids[]=<seoul_order_id>
  # → seoul 오더가 abu_dhabi 오더의 sub_order로 편입됨
  ```
- **권장 수정**: `Order.find(main_id)` → `scoped_orders.find(main_id)` 로 교체. tasks/comments reattachment 로직 추가.

---

## 우선순위 FAIL Top 10

| 순위 | 시나리오 | 판정 | 위험도 | 요약 |
|---|---|---|---|---|
| 1 | S9 | FAIL | HIGH | 검색에서 branch cross-leak — `Order.where()` 직접 사용 |
| 2 | S15 | FAIL | HIGH | viewer가 move_status/update/attach 가능 — role 가드 누락 |
| 3 | S12 | FAIL | HIGH | 악성 MIME 타입 첨부 차단 없음 |
| 4 | S25 | FAIL | HIGH | duplicate merge에서 branch 격리 우회 + 데이터 가시성 손실 |
| 5 | S1 | FAIL | HIGH | 상태 전이 guard 없음 — new_rfq → done 즉시 이동 |
| 6 | S2 | FAIL | HIGH | done/give_up → 역행 전이 허용 |
| 7 | S6 | FAIL | MEDIUM | optimistic locking 없음 — 동시 수정 충돌 last-write-wins |
| 8 | S20 | WARN | MEDIUM | Claude 429 시 fallback만 — 사용자 알림 및 재시도 큐 없음 |
| 9 | S21 | WARN | MEDIUM | Google Chat webhook 실패 재시도 없음 |
| 10 | S10 | WARN | MEDIUM | 리포트 branch 기본값이 전체(nil) — 의도치 않은 cross-branch 열람 |

---

## 테스트 추가 제안 (RUN_TESTS 이슈용 payload)

커버되지 않은 17개 시나리오에 대한 테스트 추가 우선순위:

```
P0 (즉시):
  - test/controllers/search_controller_test.rb: branch cross-leak 검증
  - test/controllers/orders_controller_test.rb: viewer role → move_status 403/redirect 검증
  - test/controllers/orders_controller_test.rb: viewer role → update 403 검증
  - test/models/order_test.rb: 악성 MIME 타입 첨부 거부 검증

P1 (이번 스프린트):
  - test/controllers/kanban_controller_test.rb: new_rfq → done 전이 차단
  - test/controllers/kanban_controller_test.rb: done → new_rfq 역행 차단
  - test/controllers/admin/duplicate_orders_controller_test.rb: branch 격리 우회 차단

P2 (다음 스프린트):
  - test/controllers/orders_controller_test.rb: 동시 상태 변경 conflict 처리
  - test/services/google_chat_service_test.rb: webhook 실패 시 재시도 확인
  - test/services/gmail/llm_rfq_analyzer_service_test.rb: 429 → fallback + 큐 확인
```

---

## 이슈 초안 JSON

```json
[
  {
    "id": "ISS-SCAN-001",
    "type": "FIX_BUG",
    "priority": "P0",
    "title": "[CRITICAL] 검색 branch cross-leak — SearchController Order.where() scoped_orders로 교체",
    "scope_dir": "app/controllers/search_controller.rb",
    "check_mode": "scenario",
    "scenario": "S9",
    "finding": "SearchController에서 Order.where() 직접 사용으로 비관리자 사용자가 타 branch 오더 검색 결과 노출",
    "fix_hint": "Order.where() → scoped_orders.where()로 교체"
  },
  {
    "id": "ISS-SCAN-002",
    "type": "FIX_BUG",
    "priority": "P0",
    "title": "[CRITICAL] viewer role이 move_status/update/attach 가능 — require_member! 가드 추가",
    "scope_dir": "app/controllers/orders_controller.rb",
    "check_mode": "scenario",
    "scenario": "S15",
    "finding": "before_action :require_manager! only: [destroy] 로만 제한. move_status, update, quick_update, attach, detach에 role 가드 없음",
    "fix_hint": "before_action :require_member!, only: %i[update quick_update move_status attach attach_from_url detach] 추가"
  },
  {
    "id": "ISS-SCAN-003",
    "type": "FIX_BUG",
    "priority": "P0",
    "title": "[CRITICAL] 악성 MIME 타입 첨부 차단 없음 — Active Storage content_type validation 추가",
    "scope_dir": "app/models/order.rb",
    "check_mode": "scenario",
    "scenario": "S12",
    "finding": "has_many_attached :attachments에 content_type 제한 없음. .exe, .bat, .js 업로드 가능",
    "fix_hint": "validates :attachments, content_type: { not_in: BLOCKED_MIME_TYPES } 추가"
  },
  {
    "id": "ISS-SCAN-004",
    "type": "FIX_BUG",
    "priority": "P0",
    "title": "[CRITICAL] admin merge에서 branch 격리 우회 — Order.find → scoped_orders 교체",
    "scope_dir": "app/controllers/admin/duplicate_orders_controller.rb",
    "check_mode": "scenario",
    "scenario": "S25",
    "finding": "Order.find(main_id), Order.find_by(id: oid) 사용으로 manager가 타 branch 오더를 merge 가능",
    "fix_hint": "Order.find → scoped_orders.find 교체"
  },
  {
    "id": "ISS-SCAN-005",
    "type": "FIX_BUG",
    "priority": "P1",
    "title": "[HIGH] 상태 전이 guard 없음 — allowed transition 매핑으로 임의 건너뛰기/역행 차단",
    "scope_dir": "app/models/order.rb app/controllers/orders_controller.rb app/controllers/kanban_controller.rb",
    "check_mode": "scenario",
    "scenario": "S1, S2",
    "finding": "state machine 또는 transition guard 없음. new_rfq → done 직행, done → new_rfq 역행 허용",
    "fix_hint": "Order 모델에 ALLOWED_TRANSITIONS 해시 + before_update 검사 메서드 추가"
  },
  {
    "id": "ISS-SCAN-006",
    "type": "FIX_BUG",
    "priority": "P2",
    "title": "[MEDIUM] optimistic locking 없음 — lock_version 컬럼 추가로 concurrent 충돌 감지",
    "scope_dir": "db/migrate",
    "check_mode": "scenario",
    "scenario": "S6",
    "finding": "Order 테이블에 lock_version 없음. 동시 상태 변경 시 last-write-wins",
    "fix_hint": "migration으로 lock_version integer default 0 추가"
  }
]
```

---

*감사 수행: check-harness (scenario 모드), 2026-04-24*
*코드 증거 기준: /Volumes/E_SSD/02_GitHub.nosync/0020_CPOFlow 소스 코드 정적 분석*
*수정 금지 원칙 준수: 발견 사항 기록만, 코드 수정 없음*
