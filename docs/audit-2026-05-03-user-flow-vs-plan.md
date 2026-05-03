# 실사용자 흐름 vs 플랜 정합성 점검 — 2026-05-03

**플랜 기준**: `brand-dna.json` — "조달/발주 9단계 워크플로를 빠르게 처리 — 정보 밀도 · SLA 신호 · 반복 업무 제거"

**점검 방법**: 운영 DB 통계 + 코드 정적 분석 + 멘션·알림·인증 플로우 추적 (Playwright 실클릭 생략 — Claude Code CLI에서 분리 처리 예정)

---

## 페르소나 4명별 핵심 저니 점검 결과

### 1) Master (admin) — 4명 등록됨 ✅
- 본인이 모든 Order, Notification, User에 접근 가능 — 정상
- **🔴 갭**: admin 4명인데 Employee 매핑된 admin은 일부만. 본인이 멘션 받을 통로 누락 가능

### 2) Member/Manager (실무자) — 6명 등록됨
- 본인 배정 카드 처리 흐름은 코드상 작동
- **🔴 갭A**: 미완료 Order 11,899건 중 **6,912건이 배정 없음** (58% 미배정) — "정보 밀도" 아젠다와 정면 충돌
- **🔴 갭B**: 미완료 Order 중 **11,825건 due_date 없음** (99% 무 SLA) — "SLA 신호" 아젠다와 정면 충돌

### 3) 신규 가입자 (viewer)
- 현재 viewer 0명. OAuth 신규 가입자는 default `:viewer`이지만 admin이 즉시 승격하는 흐름.
- **🟡 갭**: viewer 진입 후 "권한 부족" 빈 화면을 보고 이탈 가능 — 안내 문구·관리자에 알림은 있으나 사용자 본인에 onboarding 안내 부재

### 4) 외부 (guest)
- `legal_controller`, `reviews_controller` 외 인증 필수 — 정상
- **🟡 갭**: 회원가입 가능 (`/users/sign_up`) — Karpathy "외부인 가입 차단" 정책과 충돌 가능

---

## 도메인별 누적 결함

### A. 조달 데이터 위생 (Critical)
| 갭 | 수치 | 근거 |
|---|---|---|
| 배정 없는 미완료 Order | 6,912 / 11,899 (58%) | LEFT JOIN assignments WHERE NULL |
| due_date 없는 미완료 Order | 11,825 / 11,899 (99.4%) | due_date NULL count |
| `new_rfq` 컬럼에 11,838건 누적 | 칸반 1번 컬럼 폭주 | status group count |

→ **칸반 첫 컬럼이 사실상 묘지 상태**. 사용자가 "11,838건"을 보면 행동 불가능. "정보 밀도" 아젠다는 무의미해짐.

### B. 알림 시스템 일관성 (High)
| 갭 | 수치 |
|---|---|
| Notification.type=nil | 25건 (헤더 드롭다운 빈 카드) |
| `Notification::TYPES` 미등록 type | **12종** (visa/contract/overdue_unassigned_escalation 등 모두 enum 밖) |
| 미읽음 누적 | 136 / 141 (96%) — 사용자가 알림종 외면 중 |

→ 알림 enum은 5종(`due_date, status_changed, assigned, system, mentioned`)인데 실 데이터는 14종. **enum 무시하고 free-text type을 코드 곳곳에서 만들고 있음** — 탭 필터 작동 불가.

### C. 멘션 시스템 (Medium — 직전 수정으로 부분 해결)
| 갭 | 상태 |
|---|---|
| title nil 백필 | ✅ 완료 (10/10) |
| Employee.user_id 미매핑 | ❌ 5/12명 미매핑 (멘션 받기 불가) |
| 자기 자신 멘션 차단 | ✅ 정상 |
| 멘션 dropdown UI | (미점검) Stimulus 컨트롤러 작동 검증 필요 |

### D. 인증 (Critical — 별도 진행 중)
- Google OAuth `redirect_uri_mismatch` — Console에 URI 등록은 했으나 캐시/저장 확인 필요. **별도 트랙**.

### E. UI 컨벤션 (Low)
- brand-dna.json `radius=tight` (3-10px) 정의 → 안티패턴 "radius > 12px" 명시
- 칸반 카드는 `rounded-md`(7px) ✅ 부합. 실측 미수행.

---

## 제안 — 우선순위별 6개 이슈 (Claude Code CLI 처리용)

이슈 ID는 임시. 등록 후 정식 ID 부여하시면 됩니다.

### 🔴 P0 — 즉시 (1건)
- **AUDIT-001 [BIZ_DATA_HYGIENE]** — 칸반 `new_rfq` 11,838건 자동 분류·일괄 정리 정책 정의 (자동 archive 또는 batch convert)

### 🟠 P1 — 다음 스프린트 (3건)
- **AUDIT-002 [DATA_GAP]** — 미배정 Order 6,912건 자동 배정 룰 (도메인/거래처/현장별 default assignee)
- **AUDIT-003 [SLA_GAP]** — due_date 없는 Order에 default due 정책 (RFQ 수신일 + N영업일) 또는 명시적 "due 미정" 컬럼
- **AUDIT-004 [NOTIFICATION_ENUM]** — `Notification::TYPES` 확장(12종 추가) 또는 type 정규화. 탭 필터 재작동 보장.

### 🟡 P2 — 이번 분기 (2건)
- **AUDIT-005 [EMPLOYEE_USER_LINK]** — Employee.user_id 미매핑 5명 매핑 UI/Rake task. 멘션 도달률 100% 보장.
- **AUDIT-006 [VIEWER_ONBOARDING]** — viewer 첫 로그인 시 "관리자 승인 대기" 빈 화면 → 명시적 안내 + 관리자 알림 발송 확인 표시

### 🟢 P3 — 백로그 (보류)
- 멘션 dropdown UI 실클릭 검증 (Playwright)
- Notification.type=nil 25건 origin 추적 + 백필
- guest sign_up 차단 정책 결정

---

## 회귀 신호 (참고)
- 직전 멘션 수정 (`8609b3e`) 배포 시 **SENTRY_DSN 누락으로 부팅 실패** 발생 → 빈 값으로 우회 후 정상 배포. main에 들어온 sentry 통합 작업 시 secrets 동시 갱신 누락. **secret 추가는 deploy.yml 변경과 동시에 secrets 갱신을 검증하는 hook이 필요**.
