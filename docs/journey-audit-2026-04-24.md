# CPOFlow 사용자 여정 전수 검사 (2026-04-24, 배포 기준)

## 총점: 26/40
- 역할 커버리지: 5/10
- 인팩트/전환: 8/10
- 온보딩: 7/10
- 안내/에러 UX: 6/10

---

## 역할별 저니 매트릭스

| # | 저니 | 역할 | 판정 | 주 문제 |
|---|---|---|---|---|
| J1 | 첫 로그인 → 샘플 이해 | 신규 member | WARN | 온보딩 체크리스트 존재하나 샘플 데이터 없음, 빈 칸반에서 "다음 행동" CTA는 있으나 에러 발생 전 안내 부족 |
| J2 | RFQ 이메일 → 칸반 오더 전환 | member | PASS | Gmail 연결 → 인박스 → convert 흐름 완성. 단, Gmail 미연결 시 인박스 빈 상태 안내가 Settings 링크 없이 단순 텍스트로만 |
| J3 | 오더 드로어 → 첨부 → 상태 이동 | member | WARN | 드로어 "다음 단계" 버튼이 currentIdx=-1 하드코딩 버그로 항상 숨겨짐 (layout.html.erb:333). 상태 이동은 별도 폼으로만 가능 |
| J4 | 팀 KPI 조회 → 지연 오더 드릴다운 | manager | PASS | 대시보드 KPI 카드 → overdue_orders_brief로 드릴다운 지원. 단, KPI 카드 자체가 역할별 차별화 없이 admin과 동일 뷰 |
| J5 | 경영 리포트 CSV 추출 | manager | PASS | reports#export_csv 완성. 헤더 액션에 PDF/CSV/인쇄 3종 모두 존재 |
| J6 | eCount 수동 동기화 → 중복 오더 병합 | admin | WARN | 동기화 trigger POST 구현. 병합은 /admin/duplicate_orders에 분리. 진행 중 로딩 상태 없음(백그라운드 Job 완료 시까지 화면 변화 없음) |
| J7 | 직원 추가 → 비자/계약 등록 | admin | WARN | employees/_form 에서 validation 에러 표시 구현됨. 그러나 비자/계약은 직원 show 페이지의 nested resource — 직원 생성 완료 후 "비자 등록" CTA 버튼이 없어 경로를 수동 탐색해야 함 |
| J8 | 발주처 생성 → 담당자 추가 → 오더 연결 | member | WARN | 발주처 생성(new_client_path)에 Primary Action 있음. 담당자는 show에서 추가. 그러나 발주처 등록 후 자동으로 show 페이지로 이동하지 않아 담당자 추가까지 3-4클릭 필요 |
| J9 | 칸반 상태 커스터마이징 | admin | PASS | settings/card_statuses 완성. 보드 선택 + 신규 추가 + 테마 일괄 적용 모두 구현 |
| J10 | Gmail 계정 연결 → 첫 sync | admin | WARN | OAuth 흐름 완성. 그러나 callback 성공 후 Settings로 리다이렉트 — "이제 무엇을 해야 하나요?" 안내(Inbox sync 시작 CTA) 부재. 토큰 만료 시 Settings에서 빨간 경고 표시는 있으나 사이드바에는 아무 신호 없음 |

---

## 축별 발견 사항

### 축1. 역할 커버리지 (점수: 5/10)

**잘 된 점**
- 사이드바에서 `manager?` 또는 `admin?` 조건으로 "관리" 그룹 메뉴 숨김/표시 처리 (shared/_sidebar.html.erb:62-106)
- 칸반 읽기 전용 배너: `unless can_update?("orders")` 블록으로 viewer/member에게 안내 배너 노출 (kanban/index.html.erb:8-13)
- settings/menu_permissions: admin 전용 메뉴 권한 설정 기능 존재 (routes.rb:248)
- viewer가 드래그 시 "카드 이동 권한이 없습니다 (manager 이상 필요)" tooltip (kanban/index.html.erb:949)

**문제점**
- 대시보드가 역할별로 차별화되어 있지 않음. viewer/member/manager/admin 모두 동일한 전체 KPI, 비자 만료, 경영 데이터를 볼 수 있음 (dashboard_controller.rb: scoped_orders는 branch 분리만 하고 역할별 섹션 분기 없음)
  - 증거: `app/views/dashboard/index.html.erb` — `unless current_user.onboarded?` 온보딩 블록 외 역할 분기 없음
- viewer 역할이 "신규 발주" 버튼을 대시보드 상단에서 볼 수 있음 (dashboard/index.html.erb:166). 클릭하면 폼 접근 가능하나 저장 시 에러 — 비활성/숨김 처리 필요
  - 증거: `app/views/dashboard/index.html.erb:166` - `link_to new_order_path` 역할 분기 없음
- clients/index, suppliers/index, employees/index — 뷰에서 `can_create?` 가드 없이 "새 발주처 등록" 등 Create 버튼 노출 (clients/index.html.erb:10, employees/index.html.erb:10)
  - viewer가 "직원 등록", "새 발주처 등록" 버튼을 볼 수 있고, 클릭하면 폼 접근 가능 (컨트롤러 Guard가 destroy에만 있음)
  - 증거: `app/controllers/employees_controller.rb:4` — `before_action :require_manager!, only: %i[destroy]` (create는 보호 없음)
- manager 대시보드 — "팀 KPI" 섹션(담당자별 워크로드)이 하단에 위치. 0.5초 시선 룰 미달: manager가 화면 최상단에서 즉시 "팀 현황"을 볼 수 없음
- admin 홈 — Gmail 동기화 상태, eCount 동기화 현황이 사이드바/대시보드에 요약되지 않음. 시스템 건강 신호는 개별 메뉴 진입 필요

### 축2. 인팩트/전환 (점수: 8/10)

**잘 된 점**
- 대시보드 최상단 Quick Actions에 "신규 발주" Primary Action 존재 (brand-dna `MUST_EXIST` 충족): `app/views/dashboard/index.html.erb:166`
- 칸반 최상단에 보드 선택 + "신규 발주/새 카드" CTA 존재: `app/views/kanban/index.html.erb:33`
- Critical Order 즉시 조치 배너: 0건 초과 시 최상단 배너 + "확인하기" CTA (dashboard/index.html.erb:136-157)
- KPI 드릴다운: overdue 클릭 → kanban_path(filter: 'overdue') 연결 (dashboard/index.html.erb:153)
- 경영 리포트 헤더에 PDF/CSV/인쇄 3종 액션 버튼 (reports/index.html.erb:37-54)
- 빈 칸반 new_rfq 칼럼에 CTA "수동 발주 만들기" 버튼 존재 (kanban/index.html.erb:292-298)

**문제점**
- 드로어 헤더의 "다음 단계" 버튼이 항상 숨겨짐: `var currentIdx = -1;`로 하드코딩되어 있어 `currentIdx >= 0` 조건을 절대 통과하지 못함
  - 증거: `app/views/layouts/application.html.erb:333` — `var currentIdx = -1;`
  - 영향: 드로어에서 칸반 상태 이동을 한 번에 할 수 없음 (show 풀페이지 이동 필요)
- 인박스 빈 상태에서 Gmail 미연결 상황을 구별하지 않음. "메일이 없습니다" 메시지만 표시 — "Gmail 연결하러 가기" CTA 없음
  - 증거: `app/views/inbox/index.html.erb:499` — `email-empty-state` 블록에 Settings 링크 없음
- orders/index 검색 결과 없을 때 empty state CTA 미존재 (목록 뷰에서 "새 주문 만들기" CTA 부재)
- 0.5초 룰 부분 위반: manager/admin은 페이지 하단 스크롤 없이 팀 KPI를 볼 수 없음 (대시보드 KPI 카드가 전체 order 중심)

### 축3. 온보딩 (점수: 7/10)

**잘 된 점**
- ISS-240 온보딩 체크리스트 구현됨: 3단계 (Gmail 연결 → 첫 발주 → 담당자 배정) 진행 바 포함 (dashboard/index.html.erb:4-134)
- `user.onboarded?` 조건으로 완료 시 자동 숨김 (User#onboarded?: gmail_connected? && has_created_order? && has_assignment?)
- Gmail 연결 CTA가 Step 1에 직접 링크로 제공 (`gmail_oauth_authorize_path`)
- 첫 발주 CTA가 Step 2에 직접 링크 (`new_order_path`)
- Settings에도 미완료 시 안내 배너 존재 (settings/base/index.html.erb:5-17)

**문제점**
- Step 3 "담당자 배정 받기"의 CTA가 `kanban_path` — "배정받는" 행위는 관리자가 해줘야 하는데, member에게 칸반 보러 가라는 안내는 불명확. "관리자에게 요청하세요" 또는 팀원 연락처 링크가 없음
  - 증거: `app/views/dashboard/index.html.erb:123-130`
- Gmail 연결 전 인박스 화면에서 왜 메일이 없는지 안내 없음 — 신규 사용자가 Inbox 진입 시 빈 화면만 표시
  - 증거: `app/views/inbox/index.html.erb:499-510` — `email-empty-state` 블록에 조건부 안내 없음
- eCount 연동 전/후 상태 안내가 Settings에만 있고, 대시보드에서 "eCount 미연동" 알림 없음 (admin이 eCount 동기화 없이 사용할 경우 제품/거래처 데이터 부재 이유 불명확)
- 샘플 데이터(Demo Mode) 없음 — 신규 설치 후 모든 칸반 칼럼이 빈 상태, 처음 접하는 사용자가 시스템 구조 파악 어려움
- 튜토리얼/도움말 링크 없음 — 고급 기능(드로어 단축키 R/T/C/Enter, 칸반 필터, Command Palette Cmd+K) 진입점 없음

### 축4. 안내/에러 UX 품질 (점수: 6/10)

**잘 된 점**
- custom error pages 존재: `public/400.html`, `public/404.html`, `public/422.html`, `public/500.html`
- employees/_form.html.erb에 `model.errors.full_messages` 인라인 에러 표시 (employees/_form.html.erb:2-8)
- Gmail 토큰 만료 감지: Settings의 email_accounts에서 노란 점 + "재인증 필요" 텍스트 표시 (settings/base/index.html.erb:67-76)
- kanban 삭제 confirm 커스텀 모달 구현 (kanban/index.html.erb:397-428)
- 드로어 로딩 스피너: fetch 중 animate-spin 아이콘 표시 (layouts/application.html.erb:345)
- flash notice/alert가 레이아웃에서 일관되게 처리됨 (layouts/application.html.erb:137-148)

**문제점**
- Flash/Toast 불일치: `layouts/application.html.erb`는 배너형 flash, 개별 페이지(clients/show, admin/duplicate_orders)는 inline flash — 두 가지 패턴이 혼재
- 드로어 제목 수정 시 `prompt()` 사용 — 브라우저 네이티브 대화상자는 모바일에서 UI 일관성 깨짐
  - 증거: `app/views/layouts/application.html.erb:387`
- Gmail 토큰 만료 경고가 Settings에만 있고, 인박스에서 sync 실패 이유를 사용자에게 알려주지 않음. 사이드바나 대시보드 어디에도 "Gmail 재연결 필요" 신호 없음
  - 증거: shared/_sidebar.html.erb — email_accounts token 상태 체크 없음
- eCount 동기화 실패(failed_today > 0) 알림이 admin/ecount_sync 페이지에만 있음. 대시보드나 사이드바에 집계 알림 없음
- clients/index, suppliers/index 등 다수 목록 뷰에서 skeleton/로딩 인디케이터 없이 전체 렌더
- `data-turbo-confirm`은 settings/card_statuses에서만 사용, 대부분의 destructive action(병합, 상태 초기화 등)은 custom JS confirm() 또는 모달로 불일치 처리
- form validation — orders/_form (주문 폼)에서 서버사이드 에러 외 클라이언트사이드 필수 입력 안내 없음 (required 속성 미비)
- `openOrderDrawer`에서 fetch 실패 시 "네트워크 오류가 발생했습니다" 텍스트만 표시 — 재시도 버튼 없음 (layouts/application.html.erb:364-366)

---

## Top 10 개선 우선순위

### 1. [P0] 드로어 "다음 단계" 버튼 버그 수정
- 이유: `currentIdx = -1` 하드코딩으로 드로어 내 상태 이동 CTA 항상 숨겨짐. 핵심 워크플로우 단절
- 영향 저니: J3
- 증거: `app/views/layouts/application.html.erb:333`

### 2. [P0] viewer 역할 Create UI 노출 차단
- 이유: viewer가 "직원 등록", "새 발주처 등록" 버튼을 볼 수 있고 폼 접근 가능. 컨트롤러 guard 누락 → 권한 혼란
- 영향 저니: J1, J8
- 증거: `app/controllers/employees_controller.rb:4` (destroy만 보호), `app/views/clients/index.html.erb:10` (가드 없음)

### 3. [P0] 대시보드 "신규 발주" 버튼 역할 분기
- 이유: viewer도 `new_order_path` 버튼 클릭 가능. 저장 시 서버 에러 발생 가능성
- 영향 저니: J1
- 증거: `app/views/dashboard/index.html.erb:166` — `can_create?` 분기 없음

### 4. [P1] 인박스 빈 상태에서 Gmail 미연결 안내 + CTA 추가
- 이유: 신규 사용자가 Inbox 방문 시 "왜 비어있는가"를 알 수 없음. Gmail 연결 CTA 부재
- 영향 저니: J2, J10
- 증거: `app/views/inbox/index.html.erb:499` — `email-empty-state` 블록에 조건부 안내 없음

### 5. [P1] Gmail 토큰 만료 시 사이드바/대시보드 신호 추가
- 이유: 토큰 만료 경고가 Settings 내부에만 있어 대부분의 사용자가 sync 실패 이유를 인지하지 못함
- 영향 저니: J10, J2
- 증거: `app/views/shared/_sidebar.html.erb` — email_accounts 상태 체크 없음

### 6. [P1] 직원 생성 완료 후 "비자 등록" CTA 추가
- 이유: 직원 신규 등록 후 show 페이지로 리다이렉트되나 "비자 등록" 버튼 없어 경로 탐색 필요
- 영향 저니: J7
- 증거: `app/views/employees/new.html.erb` — 성공 후 CTA 없음

### 7. [P1] manager 대시보드에서 팀 KPI를 상단에 배치
- 이유: 0.5초 룰 — manager의 1순위 정보는 "팀 현황"이나 스크롤 없이 볼 수 없음
- 영향 저니: J4
- 증거: `app/controllers/dashboard_controller.rb` — `@assignee_workload`가 단일 쿼리이나 뷰 위치가 하단

### 8. [P2] 드로어 제목 수정에서 `prompt()` 제거 → 인라인 편집 개선
- 이유: 브라우저 native `prompt()`는 모바일에서 레이아웃 깨짐, 브랜드 일관성 위반
- 영향 저니: J3
- 증거: `app/views/layouts/application.html.erb:387`

### 9. [P2] eCount 동기화 실패 알림을 대시보드/사이드바에 노출
- 이유: `@failed_today > 0` 알림이 admin/ecount_sync 페이지 내부에만 있어 admin이 일상 업무 중 인지 불가
- 영향 저니: J6
- 증거: `app/controllers/admin/ecount_sync_controller.rb:13`

### 10. [P2] 발주처 생성 성공 후 show 페이지로 자동 이동 + 담당자 추가 CTA
- 이유: 발주처 생성 → 담당자 추가까지 3-4클릭 탐색 필요. "다음 단계" 안내 없음
- 영향 저니: J8
- 증거: `app/controllers/clients_controller.rb` — create 성공 시 redirect 목적지 확인 필요

---

## 이슈 초안 JSON (harness registry 삽입용)

```json
[
  {
    "type": "UX_FIX",
    "priority": "P0",
    "title": "드로어 '다음 단계' 버튼 currentIdx=-1 버그 수정",
    "payload": {
      "scope_dir": "app/views/layouts",
      "evidence": "app/views/layouts/application.html.erb:333 — var currentIdx = -1; (항상 음수라 다음 단계 버튼 숨겨짐)",
      "fix_hint": "드로어 fetch 완료 후 서버 응답에서 현재 status를 읽어 KANBAN_COLUMNS.indexOf(status)로 currentIdx 계산"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P0",
    "title": "viewer 역할의 Create UI 노출 차단 — clients/employees 뷰 + 컨트롤러 guard 추가",
    "payload": {
      "scope_dir": "app/views/clients,app/views/employees,app/controllers",
      "evidence": "app/views/clients/index.html.erb:10 / app/views/employees/index.html.erb:10 — can_create? 분기 없음. app/controllers/employees_controller.rb:4 — create 미보호",
      "fix_hint": "뷰: can_create?(:clients)/:employees 조건 추가. 컨트롤러: require_member! on create/update 추가"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P0",
    "title": "대시보드 '신규 발주' 버튼 역할 분기 추가",
    "payload": {
      "scope_dir": "app/views/dashboard",
      "evidence": "app/views/dashboard/index.html.erb:166 — viewer에게도 new_order_path 링크 노출",
      "fix_hint": "if can_create?(:orders) 조건으로 감싸거나, viewer에게는 비활성 표시"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P1",
    "title": "인박스 빈 상태에서 Gmail 미연결 안내 + Settings CTA 추가",
    "payload": {
      "scope_dir": "app/views/inbox",
      "evidence": "app/views/inbox/index.html.erb:499 — email-empty-state에 Gmail 연결 여부 조건 분기 없음",
      "fix_hint": "current_user.gmail_connected? 분기: 미연결이면 '이메일을 받으려면 Gmail 연결이 필요합니다' + gmail_oauth_authorize_path 버튼"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P1",
    "title": "Gmail 토큰 만료 시 사이드바/대시보드 상단 경고 신호 추가",
    "payload": {
      "scope_dir": "app/views/shared,app/views/dashboard",
      "evidence": "app/views/shared/_sidebar.html.erb — 이메일 계정 토큰 상태 체크 없음. 만료 시 사용자가 Settings 진입 전 인지 불가",
      "fix_hint": "sidebar nav에 current_user.email_accounts.any?(&:token_expired?) 조건으로 노란 경고 점 추가. 대시보드 상단 배너로도 노출"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P1",
    "title": "직원 생성 완료 후 show 페이지에 비자/계약 등록 CTA 버튼 추가",
    "payload": {
      "scope_dir": "app/views/employees",
      "evidence": "app/views/employees/show.html.erb — 비자/계약 섹션 존재하나 생성 직후 안내 CTA 없음",
      "fix_hint": "employees/show에서 visas.empty? && contracts.empty?인 경우 onboarding 힌트 배너 + 비자/계약 등록 링크 표시"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P1",
    "title": "manager 대시보드에서 팀 KPI(담당자별 워크로드) 상단 배치",
    "payload": {
      "scope_dir": "app/views/dashboard",
      "evidence": "app/views/dashboard/index.html.erb — @assignee_workload 섹션이 하단에 위치. 0.5초 룰 위반",
      "fix_hint": "current_user.manager? 또는 admin? 시 KPI 카드 바로 아래에 담당자 워크로드 테이블 배치"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P2",
    "title": "드로어 제목 수정을 prompt() → 인라인 편집 input으로 교체",
    "payload": {
      "scope_dir": "app/views/layouts",
      "evidence": "app/views/layouts/application.html.erb:387 — editDrawerTitle()에서 prompt() 사용. 모바일 레이아웃 깨짐 + 브랜드 일관성 위반",
      "fix_hint": "drawer-title span을 클릭 시 input[type=text]로 in-place 교체. Enter/blur 시 PATCH. 디자인 토큰 적용"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P2",
    "title": "eCount 동기화 실패 알림을 대시보드 또는 사이드바에 노출",
    "payload": {
      "scope_dir": "app/views/dashboard,app/views/shared",
      "evidence": "app/controllers/admin/ecount_sync_controller.rb:13 — @failed_today 계산되나 admin/ecount_sync 내부에만 표시",
      "fix_hint": "대시보드 하단 시스템 상태 위젯에 EcountSyncLog.failed_today.count > 0인 경우 빨간 배지 추가"
    }
  },
  {
    "type": "UX_FIX",
    "priority": "P2",
    "title": "발주처 생성 성공 후 show 페이지 자동 이동 + 담당자 추가 CTA",
    "payload": {
      "scope_dir": "app/controllers,app/views/clients",
      "evidence": "clients_controller.rb create action redirect target 확인 필요. clients/show에 신규 등록 시 담당자 추가 안내 CTA 없음",
      "fix_hint": "create 성공 redirect → client_path(@client) 확인. show 페이지에서 contact_persons.empty? 시 '담당자 등록' 강조 CTA 표시"
    }
  }
]
```

---

## 부록: 코드 증거 요약

| 파일 | 라인 | 문제 |
|---|---|---|
| `app/views/layouts/application.html.erb` | 333 | `var currentIdx = -1;` — 드로어 다음단계 버튼 항상 숨김 |
| `app/views/layouts/application.html.erb` | 387 | `prompt()` 사용 — 모바일/브랜드 위반 |
| `app/views/dashboard/index.html.erb` | 166 | `new_order_path` 역할 분기 없음 — viewer도 접근 |
| `app/views/clients/index.html.erb` | 10 | `can_create?` 가드 없이 "새 발주처 등록" 버튼 |
| `app/views/employees/index.html.erb` | 10 | `can_create?` 가드 없이 "직원 등록" 버튼 |
| `app/controllers/employees_controller.rb` | 4 | `require_manager!` only destroy — create 미보호 |
| `app/views/inbox/index.html.erb` | 499 | empty-state에 Gmail 미연결 분기 없음 |
| `app/views/shared/_sidebar.html.erb` | 전체 | Gmail 토큰 만료 신호 없음 |
| `app/views/dashboard/index.html.erb` | 전체 | 역할별 섹션 분기 없음 (viewer == admin 동일 뷰) |
