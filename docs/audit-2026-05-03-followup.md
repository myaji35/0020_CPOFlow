# Followup 점검 이슈 — 2026-05-03 (CLI 1차 구현 검수 결과)

CLI에서 AUDIT-001~009까지 8건 구현 완료 후 **운영 컨테이너에서 검증한 결과** 발견된 잔여 갭.
모두 코드는 들어왔으나 **백필/데이터 시드/실데이터 적용**이 빠진 케이스.

상위 계획 문서: `docs/audit-2026-05-03-issues.md`

---

## 🔴 P0 — Critical

### AUDIT-002-FU — Client/Supplier `default_assignee_id` 실데이터 0% (자동 배정 무력화)
- **타입**: DATA_GAP / UX
- **검수 결과**:
  - `clients.default_assignee_id` / `suppliers.default_assignee_id` 컬럼 마이그레이션 ✅ 적용됨
  - `AutoAssignerService` ✅ 정의됨
  - **그러나 운영에 default_assignee_id 채워진 Client 0/13건, Supplier 0/3건** → 자동 배정 fallback 0건 → 결국 미배정 6,912건 그대로
- **요구**:
  1. Client/Supplier 폼에서 default_assignee 입력 **필수화 또는 강한 권유 UI** (예: "기본 담당자가 없으면 미배정 카드 누적" 인라인 경고)
  2. `bin/rails order:bulk_auto_assign` 실행 후 결과 보고 (DRY_RUN 먼저 → 실제)
  3. **시드 default_assignee 추정 rake task** 신설 — 가장 많이 거래한 admin/manager를 default로 자동 추천 (대표님 검토 후 일괄 적용)
- **검증**:
  - `Client.where.not(default_assignee_id: nil).count` ≥ 10/13 (추천+검토 후)
  - 미배정 Order 수 6,912 → 50% 이하 감소
- **파일 후보**: `app/views/clients/_form.html.erb`, `app/views/suppliers/_form.html.erb`, `lib/tasks/order_assigner.rake` (실행만), `lib/tasks/seed_default_assignees.rake` (신규)
- **CLI 트리거**: 즉시 발송

---

## 🟠 P1 — High

### AUDIT-003-FU — due_date NULL 11,828건 백필 미실행
- **타입**: DATA_GAP
- **검수 결과**: `lib/tasks/order_sla_backfill.rake` 작성됨, `Order::DEFAULT_SLA_DAYS` ✅, `default_due_date_for` ✅. 그러나 **운영 미실행** → 99.4% NULL 그대로.
- **요구**:
  1. `DRY_RUN=1 bin/rails order:backfill_due_dates` 결과 확인
  2. 검토 후 실 실행
  3. 실행 후 due_date NULL 비율 확인 (목표 < 20%)
- **검증**:
  - 최근 30일 Order의 due_date NULL ≤ 5%
  - 칸반 카드 SLA 리본 색상 분포 정상화
- **파일 후보**: 코드 변경 0 — rake 실행만
- **CLI 트리거**: 즉시 발송

### AUDIT-008-FU — 잔여 type=NULL 25건 분류 백필
- **타입**: DATA_GAP / CODE_SMELL
- **검수 결과**: `validates :notification_type, presence` ✅, 신규 nil 차단됨. 하지만 **기존 25건 NULL 그대로**. CLI에서 `lib/tasks/notification_backfill.rake` 작성했지만 실행 흔적 없음.
- **요구**:
  1. `bin/rails notification:backfill` 또는 동등 명령 실행
  2. 25건 분류 결과 보고 (system 폴백 또는 origin 기반 분류)
  3. 실행 후 `Notification.where(notification_type: nil).count` = 0 확인
- **CLI 트리거**: 즉시 발송

### AUDIT-005-FU — Employee.email 비어 있어 suggested_user nil 반환
- **타입**: DATA_GAP / UX
- **검수 결과**:
  - `Employee.unmapped` scope ✅, `suggested_user` 메서드 ✅
  - 그러나 **Diego Morales 등 unmapped Employee 6명의 email 컬럼이 빈 문자열** → 1순위 매칭 실패. 2순위 이름 매칭은 User 측에 동명이인 없으면 무력
  - 결과: 매핑 자동 제안이 nil로 반환 → 멘션 도달률 회복 효과 없음
- **요구**:
  1. Employee 폼에 email 필수 입력 또는 강한 권유 (현재 빈 string 허용 중)
  2. `Employee.unmapped` 6명에 대해 이메일 수동 입력 UI 노출 (admin 직접 채움)
  3. 또는 별도 시드 rake에서 `Employee.name = User.name` 정확 일치자 자동 매핑
- **검증**: `Employee.unmapped.count` 6 → 0 또는 명시적 "외부 인력" 마킹
- **CLI 트리거**: 즉시 발송

---

## 🟡 P2 — Medium

### AUDIT-004-FU — `role_promoted` 카테고리 분류 누락
- **타입**: REFACTOR
- **검수 결과**: AUDIT-006에서 `role_promoted` notification_type 추가, AUDIT-008에서 `Notification::TYPES`에 등록. **그러나 `CATEGORY_MAP`에 매핑 누락 → category="system"으로 폴백** → 사용자 권한 승격 알림이 "시스템" 탭에 묻힘.
- **요구**:
  - `Notification::CATEGORY_MAP`에 `"role_promoted" => "role_promoted"` 추가
  - `CATEGORY_LABELS`에 `"role_promoted" => "권한 변경"` 추가
- **검증**: `Notification.new(notification_type: "role_promoted").category` == `"role_promoted"`
- **CLI 트리거**: 즉시 발송

---

## 🟢 P3 — Low

### AUDIT-001-FU — stale 0건 의미 검증 (정상 vs cleanup 사이드이펙트)
- **타입**: CODE_AUDIT
- **검수 결과**: `Order.stale_new_rfq.count == 0` — 30일 이상된 new_rfq가 운영에 0건. 이게 **정상**(최근 데이터 자동 분류 작동)인지 **`cleanup_stale_rfq` rake가 이미 실행되어 give_up으로 옮긴 부수효과**인지 불분명.
- **요구**: `Order.where(status: :give_up).where("updated_at >= ?", 7.days.ago).count` 확인. 만약 최근 give_up 이동 대량 발생 흔적이면 부작용 증거. 없으면 정상.
- **CLI 트리거**: P3 — 트리거 발송 안 함 (대표님이 시간 될 때 직접 진행)

---

## 통계 (Followup 점검 시점)

| 지표 | 값 | 비고 |
|---|---|---|
| Client.default_assignee_id 채워진 비율 | 0/13 | 🔴 무력화 |
| Supplier.default_assignee_id 채워진 비율 | 0/3 | 🔴 무력화 |
| 미배정 미완료 Order | 6,912건 | 변화 없음 (예상 — 자동 배정 룰만 깔림) |
| due_date NULL Order | 11,828건 | 백필 대기 |
| Notification.type=NULL 잔여 | 25건 | 백필 대기 |
| Employee.unmapped | 6/12명 | 이메일 누락이 차단 원인 |
| role_promoted → category | "system" 폴백 | CATEGORY_MAP 누락 |
| stale_new_rfq | 0건 | 정상 추정, 검증 필요 |

---

## CLI 트리거 발송 정책

본 followup 이슈 P0/P1/P2 항목은 작성과 동시에 `audit-trigger-cli.sh`로 **CLI 픽업 큐에 신호 발송**.
큐 위치: `.claude/cli-trigger/queue/`
픽업 명령: `bash .claude/hooks/cli-pickup-triggers.sh`
