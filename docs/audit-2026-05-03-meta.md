# Meta + 신규 점검 이슈 — 2026-05-03 (turn 후)

CLI에서 followup 5건 중 3건 commit + rake 실행 완료. 운영 검증으로 수치 확인:
- 미배정 Order **6,912 → 0** ✅
- due_date NULL **11,828 → 0** ✅
- notification_type NULL **25 → 0** ✅
- role_promoted 카테고리 분리 ✅

이제 시스템·프로세스 측면에서 발견된 갭과 새 운영 갭을 정리.

---

## 🔴 P0 — 자체 메타 (양방향 트리거 시스템 결함)

### META-01 — `audit-mark-reviewed.sh --all-current` 무차별 마킹 결함
- **타입**: HOOK_BUG
- **증상**: 직전 turn에서 점검 측이 followup 트리거 발송 직후 `--all-current` 호출 → 그 시점에 이미 origin/main에 들어와있던 **CLI 자체 push 직전 커밋들까지 자동으로 reviewed 표시됨**. 다음 세션에서 audit-detect.sh가 이를 미감지로 판정.
- **루트 원인**: `--all-current`는 origin/main HEAD까지 무조건 마킹 — 검수 진행 여부와 무관
- **요구**:
  1. `--all-current` 옵션 제거 또는 위험 표시
  2. 대안: `audit-mark-reviewed.sh <SHA>` 정확히 검수한 SHA만 명시 (단일/배치)
  3. 또는 검수 시점에 `git rev-parse HEAD`로 그 SHA만 자동 마킹 (자기 마킹 hook)
- **파일 후보**: `.claude/hooks/audit-mark-reviewed.sh`
- **CLI 트리거**: 보내지 않음 (점검 측 hook 결함이라 이 자리에서 즉시 수정)

### META-02 — CLI 측 `cli-pickup-triggers.sh --done` 미호출
- **타입**: PROTOCOL_GAP
- **증상**: 우리가 보낸 5건 트리거가 picked/done 디렉터리에 흔적 없음. CLI는 `cli-pickup-triggers.sh`를 거치지 않고 직접 docs/audit-2026-05-03-followup.md를 읽어 처리한 것으로 추정. 결과로 양방향 신호가 단방향으로 작동.
- **루트 원인**: 프로토콜 명세는 있으나 CLI 측 SessionStart hook 또는 사용자 매크로에 등록되지 않음
- **요구**:
  1. CLI 측 SessionStart hook에 cli-pickup-triggers.sh 자동 호출 추가
  2. 또는 INBOX.txt 존재 시 자동 알림 (이미 존재하면 "📨 미픽업 트리거 N건" 표시)
  3. CLI 처리 완료 시 commit 메시지에 트리거 ID 명시 + git hook이 자동 `--done` 호출
- **선결 조건**: CLI 측 환경 설정 권한
- **CLI 트리거**: META-02 자체를 트리거로 발송 → CLI가 직접 자기 SessionStart hook을 등록

---

## 🟠 P1 — 신규 운영 갭

### AUDIT-002-FU2 — Supplier default_assignee 0/3건 (시드 rake 누락 또는 거래 이력 부족)
- **타입**: DATA_GAP
- **증상**: AUDIT-002-FU 시드 rake 실행 후 Client는 10/13(77%) 채워졌는데 **Supplier는 0/3 (0%)**.
- **원인 추정**:
  - Supplier 거래 이력이 너무 적어 추정 불가 (Order 11,899건 중 supplier_id 채워진 비율 미확인)
  - 또는 시드 rake가 Client만 처리하고 Supplier는 누락
- **요구**:
  1. seed_default_assignees.rake가 Supplier도 처리하는지 코드 점검
  2. Supplier 3건의 거래 이력 통계 출력 (`bin/rails runner "Supplier.includes(:orders).each { |s| puts ... }"`)
  3. 거래 이력 0건이면 admin이 수동 지정 UI 노출 강화 (현재 amber 경고 유효)
- **CLI 트리거**: P1 발송

### AUDIT-005-FU2 — Employee.unmapped 6/12명 자동 매핑 0건 성공 (이메일/이름 데이터 부재)
- **타입**: DATA_GAP / UX
- **증상**: AUDIT-005-FU의 `auto_link_users` rake 실행 후 unmapped 6명 → 6명 그대로 (자동 매칭 0건 성공). 즉 6명 모두 이메일도 이름도 User 측에 일치하는 것이 없음.
- **요구**:
  1. unmapped 6명 명단 출력 (이름/이메일/원본 데이터)
  2. **결정 필요** — 외부 인력(공급사 직원/하청)이라 User로 만들지 말지, 또는 admin이 수동으로 User 생성 후 매핑할지
  3. "외부 인력" 마킹 컬럼 추가 검토 — `Employee.external = true`이면 unmapped scope에서 제외
- **CLI 트리거**: P1 발송

---

## 통계 (현재 시점)

| 지표 | 값 | 변화 |
|---|---|---|
| 미배정 미완료 Order | **0건** | ▼ 6,912 (-100%) ✅ |
| due_date NULL Order | **0건** | ▼ 11,828 (-100%) ✅ |
| Notification.type=NULL | **0건** | ▼ 25 (-100%) ✅ |
| Client.default_assignee | 10/13 (77%) | ▲ 0/13 |
| Supplier.default_assignee | **0/3 (0%)** | 변화 없음 ⚠️ |
| Employee.unmapped | **6/12 (50%)** | 변화 없음 ⚠️ |
| role_promoted 카테고리 | system → "role_promoted" 분리 ✅ | 매핑 OK |
