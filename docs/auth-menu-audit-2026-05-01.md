# 사이드 메뉴 권한 진단 (ISS-298)
**진단일**: 2026-05-01  
**대상**: CPOFlow Rails 8.1 · 역할 4단계(viewer / member / manager / admin)  
**진단 방법**: 읽기 전용 grep + 파일 분석 — 코드 수정 없음

---

## 1. 사이드바 메뉴 목록 (16개 항목)

파일: `app/views/shared/_sidebar.html.erb`

| # | 메뉴명 | 경로 | 그룹 | 노출 조건 |
|---|--------|------|------|----------|
| 1 | 대시보드 | `dashboard_path` | 운영 | 로그인만 (무조건 노출) |
| 2 | Inbox | `inbox_path` | 운영 | 로그인만 (무조건 노출) |
| 3 | 칸반 | `kanban_path` | 운영 | 로그인만 (무조건 노출) |
| 4 | 주문목록 | `orders_path` | 운영 | 로그인만 (무조건 노출) |
| 5 | 캘린더 | `calendar_path` | 운영 | 로그인만 (무조건 노출) |
| 6 | 팀 관리 | `team_index_path` | 운영 | 로그인만 (무조건 노출) |
| 7 | 발주처 | `clients_path` | 마스터 | 로그인만 (무조건 노출) |
| 8 | 거래처 | `suppliers_path` | 마스터 | 로그인만 (무조건 노출) |
| 9 | 외부 담당자 | `contact_persons_path` | 마스터 | 로그인만 (무조건 노출) |
| 10 | 현장 | `projects_path` | 마스터 | 로그인만 (무조건 노출) |
| 11 | 직원 관리 | `employees_path` | 마스터 | 로그인만 (무조건 노출) |
| 12 | 조직도 | `org_chart_path` | 마스터 | 로그인만 (무조건 노출) |
| 13 | 경영 리포트 | `reports_path` | 관리 | **manager 이상** (줄 82) |
| 14 | eCount (서브메뉴 4개) | `/admin/ecount/*` | 관리 | **manager 이상** (줄 82) |
| 15 | 메뉴 권한 | `settings_menu_permissions_path` | — | **admin 전용** (줄 127) |
| 16 | 피드백 관리 | `admin_reviews_path` | — | **admin 전용** (줄 127) |
| (공통) | 휴지통 | `trash_path` | 푸터 | 로그인만 (무조건 노출) |
| (공통) | 설정 | `settings_root_path` | 푸터 | 로그인만 (무조건 노출) |

**핵심 관찰**: 사이드바에 role-guard가 있는 항목은 `관리` 그룹(manager+)과 admin 전용 2개뿐.  
`마스터` 그룹 6개(발주처·거래처·외부담당자·현장·직원관리·조직도)는 **viewer 포함 전원에게 무조건 노출**.

---

## 2. 컨트롤러 가드 매트릭스

### 공통 베이스
- `ApplicationController` — `before_action :authenticate_user!` (전체 적용)
- 역할 메서드 정의 (User enum): `viewer(0) / member(1) / manager(2) / admin(3)`

### 헬퍼 메서드
| 메서드 | 정의 위치 | 허용 역할 |
|--------|----------|----------|
| `require_member!` | ApplicationController:69 | member, manager, admin |
| `require_manager!` | ApplicationController:62 | manager, admin (`admin_or_manager?`) |
| `require_admin!` | ApplicationController:77 | admin 전용 |
| `require_admin_or_manager!` | ReportsController:264 | admin, manager |
| `require_manager_or_admin!` | Orders::BulkController:47 | admin, manager |
| `authorize_admin!` | Settings::NotificationsController:33 | admin, manager |
| `require_admin` (bang 없음) | Settings::ApiKeysController:51 | admin 전용 |

### 컨트롤러별 가드 상세

| 컨트롤러 | 파일 | 가드 범위 | 허용 최소 역할 |
|---------|------|----------|--------------|
| DashboardController | dashboard | 없음 (authenticate_user!만) | viewer |
| InboxController | inbox | member 이상: write/AI 액션만 | member (읽기: viewer) |
| KanbanController | kanban | member 이상: move/merge/split | member (보기: viewer) |
| OrdersController | orders | member: CRUD, manager: destroy | member (목록/조회: viewer) |
| Orders::BulkController | orders/bulk | manager 이상 (전체) | manager |
| Orders::PdfController | orders/pdf | 없음 (authenticate_user!만) | viewer |
| CalendarController | calendar | 없음 (authenticate_user!만) | viewer |
| TeamController | team | index/show: viewer도 가능; update_role: admin만 (줄 100) | viewer (수정: admin) |
| ClientsController | clients | member: new/create/edit/update, manager: destroy | member (조회: viewer) |
| SuppliersController | suppliers | member: new/create/edit/update (destroy 없음) | member (조회: viewer) |
| ContactPersonsController | contact_persons | authenticate_user!만 (role guard 없음) | **viewer (CRUD 무방비)** |
| ProjectsController | projects | member: new/create/edit/update, manager: destroy | member (조회: viewer) |
| EmployeesController | employees | member: new/create/edit/update, manager: destroy | member (조회: viewer) |
| EmploymentContractsController | employment_contracts | authenticate_user!만 | **viewer (CRUD 무방비)** |
| VisasController | visas | authenticate_user!만 | **viewer (CRUD 무방비)** |
| CertificationsController | certifications | authenticate_user!만 | **viewer (CRUD 무방비)** |
| OrgChartController | org_chart | 없음 (authenticate_user!만) | viewer |
| OrgChart::CompaniesController | org_chart/companies | manager 이상 (전체) | manager |
| OrgChart::CountriesController | org_chart/countries | admin 전용 (전체) | admin |
| OrgChart::DepartmentsController | org_chart/departments | manager 이상 (전체) | manager |
| ReportsController | reports | admin_or_manager! (전체) | manager |
| TrashController | trash | 조회: authenticate; 영구삭제(purge_all): admin만 | viewer (영구삭제: admin) |
| SearchController | search | authenticate_user!만 | viewer |
| AgentInsightsController | agent_insights | authenticate_user!만 | viewer |
| Settings::BaseController | settings/base | authenticate_user!만 | viewer |
| Settings::ProfileController | settings/profile | authenticate_user!만 | viewer |
| Settings::EmailAccountsController | settings/email_accounts | authenticate_user!만 | viewer (본인 메일계정 CRUD) |
| Settings::MenuPermissionsController | settings/menu_permissions | require_admin! (전체) | admin |
| Settings::ApiKeysController | settings/api_keys | require_admin (bang 없음) | admin |
| Settings::KanbanBoardsController | settings/kanban_boards | require_admin! (전체) | admin |
| Settings::KanbanColumnsController | settings/kanban_columns | require_admin! (전체) | admin |
| Settings::CardStatusesController | settings/card_statuses | 없음 (authenticate_user!만) | **viewer (카드상태 CRUD 무방비)** |
| Settings::TrackingCodesController | settings/tracking_codes | require_admin! (전체) | admin |
| Settings::NotificationsController | settings/notifications | authorize_admin! (admin/manager) | manager |
| Settings::AgentTrustController | settings/agent_trust | authenticate_user!만 | viewer |
| Admin::EcountSyncController | admin/ecount_sync | require_manager! (전체) | manager |
| Admin::ImportsController | admin/imports | require_manager! (전체) | manager |
| Admin::Ecount::ProductsController | admin/ecount/products | require_manager! (전체) | manager |
| Admin::Ecount::TransactionsController | admin/ecount/transactions | require_manager! (전체) | manager |
| Admin::Ecount::CustomersController | admin/ecount/customers | require_manager! (전체) | manager |
| Admin::ReviewsController | admin/reviews | require_admin! (전체) | admin |
| Admin::SheetsConfigController | admin/sheets_config | require_admin! (전체) | admin |
| Employees::DepartmentsController | employees/departments | require_manager! (전체) | manager |
| Employees::JobTitlesController | employees/job_titles | require_manager! (전체) | manager |
| GmailOAuthController | gmail_oauth | authenticate_user!만 | viewer |
| NotificationsController | notifications | authenticate_user!만 | viewer |
| ReviewsController | reviews | skip: new/create | 비로그인 포함 |

---

## 3. MenuPermission 모듈 활용도 분석

### DB 구조
- 마이그레이션: `db/migrate/20260221061433_create_menu_permissions.rb`
- 테이블: `menu_permissions` (role, menu_key, can_read, can_create, can_update, can_delete)
- 유니크 인덱스: `[role, menu_key]`

### MENU_KEYS 정의 (MenuPermission 모델)
```
%w[orders clients suppliers projects employees org_chart inbox kanban admin]
```

### 실제 활용 현황
| 항목 | 상태 |
|------|------|
| DB 스키마 | 존재 (schema.rb 확인) |
| 헬퍼 메서드 (`can_read?` 등) | ApplicationController에 정의, helper_method 등록 |
| 뷰에서 활용 | `orders/index`, `orders/show`, `orders/_sidebar_panel`, `kanban/index` 4개 파일만 사용 |
| 컨트롤러 enforcement | **미적용** — `can_read?`를 컨트롤러 before_action으로 사용하는 곳 없음 |
| 사이드바 노출 제어 | **미적용** — 사이드바는 `current_user.manager?` 직접 체크, DB 기반 아님 |

### MenuPermission MENU_KEYS vs 사이드바 항목 불일치
- `contact_persons` — MenuPermission에 키 없음 (사이드바에 있음)
- `calendar` — MenuPermission에 키 없음 (사이드바에 있음)
- `team` — MenuPermission에 키 없음 (사이드바에 있음)
- `reports` — MenuPermission에 키 없음 (사이드바 관리 그룹에 있음)
- `admin` 키 — MenuPermission에 있으나 사이드바 단독 항목 없음 (eCount 서브메뉴 전체)

---

## 4. 역할 x 메뉴 노출 매트릭스 (완성표)

> V = 노출 + 접근 가능 / R = 읽기만 / X = 차단 / L = 사이드바 미노출 + URL 차단

| 메뉴 | viewer | member | manager | admin | 비고 |
|------|--------|--------|---------|-------|------|
| 대시보드 | V | V | V | V | |
| Inbox (조회) | V | V | V | V | |
| Inbox (AI/변환/삭제) | X | V | V | V | require_member! |
| 칸반 (보기) | V | V | V | V | can_read?("orders") 뷰 체크 |
| 칸반 (이동/병합) | X | V | V | V | require_member! |
| 주문목록 (조회) | V | V | V | V | |
| 주문목록 (CRUD) | X | V | V | V | require_member! |
| 주문 삭제 | X | X | V | V | require_manager! |
| 주문 일괄처리 | X | X | V | V | require_manager_or_admin! |
| 캘린더 | V | V | V | V | role guard 없음 |
| 팀 관리 (조회) | V | V | V | V | |
| 팀 관리 (역할변경) | X | X | X | V | admin 전용 (줄 100) |
| 발주처 (조회) | V | V | V | V | |
| 발주처 (CRUD) | X | V | V | V | require_member! |
| 발주처 (삭제) | X | X | V | V | require_manager! |
| 거래처 (조회) | V | V | V | V | |
| 거래처 (CRUD, 삭제 없음) | X | V | V | V | require_member! |
| 외부 담당자 (전체) | V(!) | V | V | V | **role guard 전무** |
| 현장 (조회) | V | V | V | V | |
| 현장 (CRUD) | X | V | V | V | require_member! |
| 현장 (삭제) | X | X | V | V | require_manager! |
| 직원 관리 (조회) | V | V | V | V | |
| 직원 관리 (CRUD) | X | V | V | V | require_member! |
| 직원 관리 (삭제) | X | X | V | V | require_manager! |
| 고용계약 (전체) | V(!) | V | V | V | **role guard 전무** |
| 비자 (전체) | V(!) | V | V | V | **role guard 전무** |
| 자격증 (전체) | V(!) | V | V | V | **role guard 전무** |
| 조직도 (조회) | V | V | V | V | |
| 조직도 (회사/부서 관리) | X | X | V | V | manager+ (사이드바 없음) |
| 조직도 (국가 관리) | X | X | X | V | admin 전용 (사이드바 없음) |
| 경영 리포트 | X | X | V | V | 사이드바도 manager+ |
| eCount 메뉴 | X | X | V | V | 사이드바도 manager+ |
| 메뉴 권한 설정 | L | L | L | V | admin 전용 |
| 피드백 관리 | L | L | L | V | admin 전용 |
| 휴지통 (조회/복원) | V | V | V | V | branch 격리만 |
| 휴지통 (영구삭제) | X | X | X | V | admin 전용 |
| 설정 (본인 프로필/테마) | V | V | V | V | |
| 설정 (알림) | X | X | V | V | authorize_admin! |
| 설정 (이메일 계정) | V | V | V | V | 본인 메일만 |
| 설정 (API 키) | L | L | L | V | admin 전용 |
| 설정 (칸반 보드) | L | L | L | V | admin 전용 |
| 설정 (칸반 컬럼) | L | L | L | V | admin 전용 |
| 설정 (카드 상태) | V(!) | V | V | V | **role guard 전무** |
| 설정 (트래킹 코드) | L | L | L | V | admin 전용 |

`V(!)` = 보안 갭 — viewer가 CRUD 가능한 위험 영역

---

## 5. 갭 분류 (A/B/C/D)

### 패턴 A — 노출은 되는데 컨트롤러가 막음 (UX 문제)

| 항목 | 사이드바 노출 | 컨트롤러 결과 |
|------|-------------|--------------|
| Inbox AI 기능 | viewer에게 노출 | require_member!로 차단 |
| 칸반 카드 이동 | viewer에게 노출 | require_member!로 차단 |

**심각도**: MEDIUM — viewer가 버튼 클릭 후 튕기는 혼란 UX. 칸반 뷰는 `can_update?("orders")` 체크로 일부 보완됨 (`kanban/index.html.erb` 줄 8, 910).

---

### 패턴 B — 노출도 되고 가드도 없음 (보안 문제)

**B-1. ContactPersonsController (외부 담당자)**  
근거: `app/controllers/contact_persons_controller.rb` 줄 2 — `before_action :authenticate_user!`만 존재.  
`new`, `create`, `edit`, `update`, `destroy` 전부 viewer도 실행 가능.  
**심각도**: HIGH

**B-2. EmploymentContractsController (고용계약)**  
근거: `app/controllers/employment_contracts_controller.rb` 줄 2-4 — authenticate_user!만.  
직원 고용계약 생성/수정/삭제를 viewer도 가능.  
**심각도**: CRITICAL (급여/계약 민감 정보)

**B-3. VisasController (비자 관리)**  
근거: `app/controllers/visas_controller.rb` 줄 2-4 — authenticate_user!만.  
직원 비자 생성/수정/삭제를 viewer도 가능.  
**심각도**: HIGH

**B-4. CertificationsController (자격증)**  
근거: `app/controllers/certifications_controller.rb` 줄 2 — authenticate_user!만.  
자격증 CRUD를 viewer도 가능.  
**심각도**: MEDIUM

**B-5. Settings::CardStatusesController (카드 상태)**  
근거: `app/controllers/settings/card_statuses_controller.rb` 줄 5-6 — role guard 없음.  
카드 상태 이름/색상 추가·수정·삭제를 viewer도 가능.  
**심각도**: HIGH (전체 칸반 보드 설정 훼손)

---

### 패턴 C — DB 기반 권한 매트릭스 미활용

`MenuPermission` 모델과 `can_read?` / `can_create?` / `can_update?` / `can_delete?` 헬퍼가 ApplicationController에 정의되어 있으나 컨트롤러 before_action으로 enforcement하는 곳이 없음.

현재 사용 현황:
- `kanban/index.html.erb` — CAN_MOVE_ORDERS 판단 (JS 변수)
- `orders/index.html.erb`, `orders/show.html.erb`, `orders/_sidebar_panel.html.erb` — 버튼 노출 여부

**모순**: MenuPermission DB에서 viewer의 `can_create?(orders) = false`를 설정해도 `OrdersController`의 `before_action :require_member!`는 menu_permission을 읽지 않고 User.role만 직접 확인. DB 변경이 컨트롤러 접근에 영향 없음.

**심각도**: HIGH — 관리자가 UI에서 권한을 변경해도 실제 보안에 영향 없는 "가짜 권한 관리" 상태.

---

### 패턴 D — 역할별 정책 불명확

**D-1. `require_manager!` 계열 메서드 3개 혼재**  
- `ApplicationController::require_manager!` (줄 62) — 내부에서 `admin_or_manager?` 호출
- `ReportsController::require_admin_or_manager!` (줄 264) — 같은 역할 집합 로컬 재정의
- `Orders::BulkController::require_manager_or_admin!` (줄 47) — 또 다른 이름
- 동일 규칙 3개 다른 이름 → 유지보수 위험

**D-2. `require_admin` (bang 없음) 사용**  
`Settings::ApiKeysController` 줄 5: `before_action :require_admin`  
bang 없는 메서드는 로컬 재정의(줄 51). ApplicationController의 `require_admin!`과 다른 경로로 작동. 일관성 없음.

**D-3. MenuPermission MENU_KEYS 미완성**  
DB에 등록된 키: `orders, clients, suppliers, projects, employees, org_chart, inbox, kanban, admin`  
사이드바 항목이지만 키 없음: `contact_persons`, `calendar`, `team`, `reports`  
이 메뉴들은 UI 권한 관리 화면에서 설정 불가능.

---

## 6. 우선순위

| 순위 | 패턴 | 항목 | 심각도 |
|------|------|------|--------|
| P0 | B-2 | EmploymentContractsController — role guard 전무 | CRITICAL |
| P0 | C | MenuPermission DB 값이 컨트롤러 enforcement 미반영 ("가짜 권한관리") | CRITICAL |
| P1 | B-1 | ContactPersonsController — role guard 전무 | HIGH |
| P1 | B-3 | VisasController — role guard 전무 | HIGH |
| P1 | B-5 | Settings::CardStatusesController — role guard 전무 | HIGH |
| P1 | D-1 | require_manager 계열 3개 혼재 | HIGH |
| P2 | B-4 | CertificationsController — role guard 전무 | MEDIUM |
| P2 | D-3 | MenuPermission MENU_KEYS 4개 누락 (contact_persons·calendar·team·reports) | MEDIUM |
| P3 | A | viewer 사이드바 노출 + 클릭 후 차단 UX | MEDIUM |
| P3 | D-2 | require_admin vs require_admin! 혼재 | LOW |

---

## 7. 권장 개선안

### 단기 — P0/P1 즉시 수정

**민감 컨트롤러 최소 가드 추가**

```ruby
# employment_contracts_controller.rb — 줄 2 다음 추가
before_action :require_member!

# visas_controller.rb — 줄 2 다음 추가
before_action :require_member!

# contact_persons_controller.rb — 줄 2 다음 추가
before_action :require_member!, only: %i[new create edit update destroy create_from_signature]

# settings/card_statuses_controller.rb — 줄 5 다음 추가
before_action :require_manager!
```

### MenuPermission 활용 방향 결정

옵션 A (권장): 현재 `require_member!` 방식 유지 + MenuPermission은 뷰 노출 제어 전용으로 문서화. "메뉴 권한 설정" UI에 "버튼 노출만 제어합니다. 접근 통제는 시스템 역할로 관리됩니다" 안내 추가.

옵션 B: `before_action { redirect_to root_path unless can_read?(:orders) }` 패턴으로 DB 기반 전환 — 구현 복잡도 높고 DEFAULT_PERMISSIONS 재검토 필요.

### 중기 — P1/P2

**require_manager! 계열 통합** (application_controller.rb 정리)  
**MenuPermission MENU_KEYS 확장**: `contact_persons, calendar, team, reports` 추가
