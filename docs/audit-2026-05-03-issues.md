# 점검 이슈 목록 — 2026-05-03

플랜(brand-dna.json — 정보 밀도 / SLA 신호 / 반복 업무 제거) 대비 실 운영 데이터 갭. Claude Code CLI에서 처리.

상세 점검 보고서: `docs/audit-2026-05-03-user-flow-vs-plan.md`

---

## 🔴 P0 — Critical (즉시)

### AUDIT-000 — 클라이언트 합의 북극성 "RFQ 처리 48h → 10min" 미문서화 ⭐ NEW (정정)
- **타입**: NORTH_STAR / SCOPE_DEFINE / FEATURE_PLAN
- **사실 정정**: 직전 답변에서 "기획되지 않았다"고 했으나 **틀렸음**. 대표님 증언으로 **클라이언트와 "기존 48시간 → 10분 이내" 합의 사실 존재**. 또한 어제(2026-05-02) `docs/biz-automation-opportunities-2026-05-02.md`에 단계별 baseline·자동화 후 시간이 이미 분석되어 있음.
- **현 상태**: 합의·분석 둘 다 존재하지만 **공식 플랜 문서(brand-dna.json/getting-started.md/dashboard KPI)에 흡수가 안 됨** → 코드·UI에 측정·표시 없음 → AUDIT-001~003 같은 누적 증상 발생.

**클라이언트 합의 (대표님 증언)**:
- Baseline: **RFQ 수신 → 견적 발송 평균 48시간**
- Target: **10분 이내**
- 단축 비율: **288배 (≈99.65%)**

**기존 자동화 분석 결과 (`docs/biz-automation-opportunities-2026-05-02.md`)**:
| 단계 | 현재 부담 | 자동화 후 | ROI |
|---|---|---|---|
| make_quo A: 과거 단가 견적 초안 | 15~20분 | 2~3분 | ★★★★★ |
| make_quo B: 공급사 자동 추천 | 20~30분 | 3분 | ★★★★★ |
| make_quo C: 다수 공급사 견적 일괄 발송 | 30~45분 | 5분 | ★★★★☆ |
| pending_po D: PO 수신 자동 인식 | 10~15분 | 1~2분 | ★★★★★ |
| pending_po E: PO 번호 자동 추출 | 5분 | ~0분 | ★★★★★ |
| **단계별 합산 (자동화 후)** | — | **~10~15분** | — |

→ 자동화 후 시간 합산이 정확히 **10분대 (목표와 일치)**. 즉 클라이언트 합의는 이미 기술 분석으로 뒷받침되어 있음.

- **요구**:
  1. **brand-dna.json에 `north_star_metric` 섹션 추가** — `{baseline: "48h", target: "10min", scope: "RFQ 수신 → 견적 발송"}`
  2. **`docs/north-star.md` 새 문서** — 클라이언트 합의 맥락 + 단계별 자동화 후 분배 시간 + 측정 방법
  3. **Order에 단계 진입 시각 기록** — `status_changed_at` 또는 `OrderStatusHistory` (이거 없으면 baseline 측정 불가능)
  4. **대시보드 상단 북극성 KPI 카드** — "지난 7일 평균 RFQ→견적 시간: NN분 (목표: 10분)" + 추세 스파크라인
  5. **AUDIT-001~003 우선순위 재조정** — 북극성 달성 경로상 직접 영향 있는 것이 P0, 나머지는 P1로 격하
- **파일 후보**: `brand-dna.json`, `docs/north-star.md`(신규), `db/migrate/...status_changed_at.rb`(신규) 또는 `db/migrate/...order_status_histories.rb`(신규), `app/models/order.rb`, `app/views/dashboards/index.html.erb`
- **검증 (Goal-Driven)**:
  - brand-dna.json에 north_star_metric 추가 ✓
  - 새 Order의 단계 전환 시각 기록 동작 확인 (`Order.status_changed_at` 또는 history row 생성) ✓
  - 대시보드에서 평균 lead time 숫자 노출 ✓
  - 자동화 로드맵(Q1~Q4) 항목과 north star 진행률 연결 ✓
- **블로킹 해소**: AUDIT-001/002/003은 본 이슈가 먼저 정의돼야 "어디까지 줄여야 성공인지" 명확해짐. AUDIT-000이 데이터 측정 인프라(status_changed_at)도 함께 깔아주므로 후속 이슈의 baseline 측정 도구로도 작동.
- **이전 답변 정정**: 직전 응답("플랜에 부재")은 plan 문서 기준 검색 결과를 보고했지만, **사람의 합의 + 분석 자료는 존재**했음. plan 문서 동기화가 누락된 케이스. 이런 종류의 갭을 잡기 위해 AUDIT-000-meta로 "구두 합의 → plan 문서 흡수 누락" 유형의 갭 점검 hook도 검토 가치 있음.

### AUDIT-001 — 칸반 `new_rfq` 11,838건 정리 정책
- **타입**: BIZ_DATA_HYGIENE
- **증상**: 칸반 첫 컬럼(`new_rfq`)에 Order 11,838건 누적. UI 렌더링 부담 + 사용자 행동 불가.
- **원인 추정**: Gmail 자동 RFQ 분류 후 후속 흐름 없음. archive 정책 부재.
- **요구**:
  1. 30일 무동작 `new_rfq` Order 자동 `give_up` 또는 별도 archive 컬럼 이동 정책 정의
  2. 일괄 처리 rake task 또는 Solid Queue job
  3. 칸반 `new_rfq` 컬럼에 "최근 30일만 표시 + 보기 더보기" 페이지네이션
- **파일 후보**: `app/models/order.rb`, `app/jobs/`, `app/views/kanban/index.html.erb`
- **검증**: 칸반 첫 컬럼 표시 건수 < 100건. 일괄 처리 후 done/give_up 카운트 증가 확인.

---

## 🟠 P1 — High (다음 스프린트)

### AUDIT-002 — 미배정 Order 6,912건 자동 배정 룰
- **타입**: DATA_GAP / FEATURE_PLAN
- **증상**: 미완료 Order 11,899건 중 6,912건(58%) 배정자 없음. 책임 추적 불가.
- **요구**:
  1. Order 도메인/거래처(client_id)/현장(project_id) 기반 default assignee 매핑 테이블
  2. Order 생성/RFQ 분류 시 자동 배정 hook
  3. 매핑 없는 경우 "미배정 Order" 대시보드 카드 (admin이 일괄 처리)
- **파일 후보**: `app/services/auto_assigner_service.rb` (신규), `app/models/order.rb`, `app/controllers/orders_controller.rb`
- **검증**: 신규 Order 생성 시 자동 배정 로그 + 미배정 카운트 추세 감소.

### AUDIT-003 — due_date 없는 Order 11,825건 SLA 정책
- **타입**: SLA_GAP / FEATURE_PLAN
- **증상**: 미완료 Order 11,899건 중 11,825건(99.4%) due_date NULL → SLA 신호 표시 불가 → 칸반 리본 무력화.
- **요구**:
  1. RFQ 분류 단계별 default SLA (예: new_rfq → +3영업일, make_quo → +5영업일)
  2. due_date 없을 때 카드에 "due 미정" 명시 배지
  3. 일괄 backfill rake (보수적 — 30일 이내만)
- **파일 후보**: `app/models/order.rb`, `app/views/kanban/_card.html.erb`, `db/migrate/`
- **검증**: due_date NULL 비율 < 20%. 카드 SLA 리본 색상 분포 정상화.

### AUDIT-004 — Notification.type enum 정규화
- **타입**: NOTIFICATION_ENUM / REFACTOR
- **증상**: `Notification::TYPES`는 5종 정의(`due_date, status_changed, assigned, system, mentioned`)인데 실 DB에 12종 free-text type 존재 (`visa_*`, `contract_*`, `overdue_unassigned_escalation`, `ecount_slip_failed_*`, `due_date_d0/d3/d7`, `new_oauth_user`). `/notifications` 페이지 탭 필터에 매칭 안 됨 → 사용자가 받은 알림을 못 찾음.
- **요구**:
  1. `Notification::TYPES` 확장 또는 그룹화 (예: `due_date_d0` → `due_date`로 정규화)
  2. 탭 추가 또는 카테고리 매퍼 helper
  3. nil type 25건 백필
- **파일 후보**: `app/models/notification.rb`, `app/views/notifications/index.html.erb`, `app/views/shared/_header.html.erb`
- **검증**: 모든 알림이 적어도 1개 탭에 매칭. 탭별 카운트 합 = 전체 카운트.

---

## 🟡 P2 — Medium (이번 분기)

### AUDIT-005 — Employee.user_id 미매핑 5명 매핑 UX
- **타입**: USER_STORY / DATA_GAP
- **증상**: Employee 12명 중 5명이 user_id NULL → 멘션 시 알림 못 받음. `MentionParserService#resolve_employee` 통과해도 `next unless employee&.user_id`에서 스킵.
- **요구**:
  1. admin이 Employee 편집 화면에서 User 매핑 dropdown
  2. 자동 매핑 제안 (이름/이메일 매치)
  3. 미매핑 Employee 대시보드 카드 (admin 알림)
- **파일 후보**: `app/views/employees/_form.html.erb`, `app/controllers/employees_controller.rb`
- **검증**: Employee.where(user_id: nil).count → 0 또는 명시적 "외부인" 마킹.

### AUDIT-006 — viewer 첫 로그인 onboarding 가이드
- **타입**: UX_FIX
- **증상**: OAuth 신규 가입자는 default `:viewer`. 첫 로그인 시 권한 부족으로 칸반/오더 빈 화면. admin 승인 대기 안내 부재.
- **요구**:
  1. viewer 권한 시 dashboard에 "승인 대기" 안내 카드 (현재 admin에게 알림 갔음 표시)
  2. admin 권한 승격 시 Notification으로 사용자에게 알림
  3. 사용자 본인 정보 수정(이름/branch)은 viewer도 가능하도록
- **파일 후보**: `app/views/dashboards/index.html.erb`, `app/policies/` (Pundit), `app/controllers/users/omniauth_callbacks_controller.rb`
- **검증**: viewer 첫 로그인 후 빈 화면 대신 안내 노출.

---

## 🟢 P3 — Low (백로그)

### AUDIT-007 — 멘션 dropdown 실클릭 검증
- **타입**: BROWSER_QA
- **증상**: `data-controller="mention"` Stimulus 컨트롤러 + `mention_suggestions_path` AJAX 검색. 실제 입력→드롭다운→선택→@이름 삽입 흐름 미검증.
- **요구**: Playwright 시나리오 1건 (코멘트 폼에 "@" 타이핑 → 드롭다운 노출 → 첫 항목 클릭 → 입력 반영 확인)
- **파일 후보**: `app/javascript/controllers/mention_controller.js`, `test/system/`

### AUDIT-008 — Notification.type=nil 25건 origin 추적
- **타입**: CODE_SMELL
- **증상**: type 컬럼 NULL인 Notification 25건. 어디서 type 없이 create했는지 추적 필요.
- **요구**: `grep -rn "Notification.create" app/` → type 누락 location 식별, validates :notification_type, presence: true 추가 검토.
- **파일 후보**: `app/models/notification.rb`, `app/services/`, `app/jobs/`

### AUDIT-009 — guest sign_up 차단 정책 결정
- **타입**: SECURITY / SCOPE_DEFINE
- **증상**: `/users/sign_up` 라우트 활성. 외부인 가입 후 viewer로 진입 가능. Karpathy "외부 노출 차단" 정책과 정합성 검토 필요.
- **결정 항목**:
  - (a) `:registerable` Devise 모듈 제거 → admin 초대만 허용
  - (b) sign_up 유지하되 회사 도메인(`@ddtl.co.kr`, `@atoz2010.ae`) 화이트리스트 검증
  - (c) 현행 유지 (viewer로 차단됨)
- **파일 후보**: `app/models/user.rb`, `config/routes.rb`, `app/controllers/users/registrations_controller.rb`

---

## 회귀 신호 (참고 — 신규 이슈 아님)

- **REGRESSION-2026-05-03**: main에 `SENTRY_DSN` 추가 시 `.kamal/secrets` 동시 갱신 누락 → 운영 부팅 실패. 빈 값 임시 우회로 해결. **deploy.yml secret 추가 PR에는 secrets 갱신 체크리스트 hook 필요**.

---

## 통계 스냅샷 (점검 시점)

| 지표 | 값 |
|---|---|
| User | 10명 (admin 4 / manager 1 / member 5 / viewer 0) |
| OAuth 가입자 | 2명 |
| Order | 11,899건 (new_rfq 11,838 / 나머지 8단계 합 61) |
| 미완료 Order | 11,899건 |
| 미배정 Order | 6,912건 (58%) |
| due_date 없는 Order | 11,825건 (99.4%) |
| Overdue (미완 + due 지남) | 24건 |
| Notification | 141건 (unread 136 / 96%) |
| Comment | 16건 (@ 포함 9건) |
| 멘션 알림 | 10건 (백필 후 title 100% 채워짐) |
| Employee user_id 미매핑 | 5/12명 |
| Client / Supplier / Project | 13 / 3 / 5 |
| 최근 7일 신규 Order | 691건 |
| 최근 7일 신규 Notification | 118건 |
