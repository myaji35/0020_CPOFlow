# CPOFlow 시작하기 (3분 튜토리얼)

조달/발주 9단계 워크플로를 빠르게 처리하기 위한 CPOFlow 가이드입니다.

---

## 1. 첫 3단계 체크리스트

대시보드 상단 "시작하기" 카드의 3단계를 완료하면 CPOFlow를 바로 활용할 수 있습니다.

### Step 1 — Gmail 연결
- `설정 > 이메일 계정 > Gmail 연결하기` 클릭
- OAuth 동의 후 자동으로 15분마다 RFQ 메일을 Inbox로 수집
- 실패 시 대시보드 상단에 빨간 배너 자동 노출 → "다시 연결" 클릭

### Step 2 — 첫 발주 만들기
두 가지 경로가 있습니다.

- **A. 메일에서 자동 변환**: Inbox 상단 "견적성 메일" 탭의 후보 → "칸반으로 이동" 클릭
- **B. 수동 생성**: `대시보드 > 신규 발주` 또는 `오더 > + 새 발주`

### Step 3 — 담당자 배정 받기
- 칸반 카드 또는 드로어 상단에서 "담당자 추가" → 직원 선택
- 매니저가 일괄 배정하려면 `대시보드 > 팀 과부하 TOP 3 > 상세`

---

## 2. 9단계 칸반 이해하기

```
new_rfq  →  make_quo  →  pending_po  →  new_po  →  delivery_items  →  get_grn  →  done
                                                         ↓ (문제 발생 시)
                                                      problem
                                                         ↓
                                                     delivery_items / get_grn / new_po(재발주)

  ↓ (어느 단계든 포기 가능)
give_up  →  (복구) new_rfq
```

**규칙 (ISS-265 상태머신)**:
- 건너뛰기 불가 (예: `new_rfq → pending_po` 차단)
- 역행 불가 (예: `done → new_rfq` 차단)
- give_up → new_rfq 재개는 드로어 "재개 (New로 되돌리기)" CTA
- admin은 필요 시 수동 정정 가능 (force_transition)

---

## 3. 역할과 권한

| 역할 | 권한 |
|---|---|
| viewer | 읽기만 가능 (Create 버튼 비노출) |
| member | CRUD + 상태 이동 + 첨부/댓글/할일/견적/담당자 배정 |
| manager | member + 일괄 편집, destroy, 팀 KPI 드릴다운 |
| admin | 전체 + 상태 전이 규칙 우회, 브랜치 전체 접근, 중복 오더 병합 |

신규 가입자는 `viewer` 권한으로 시작 — admin이 수동 승격해야 작업 가능 (ISS-259).

---

## 4. 브랜치 격리 (abu_dhabi / seoul)

오더는 생성자의 브랜치에 묶여 상호 노출되지 않습니다. 관리자만 전체 브랜치 접근.

Google OAuth 가입 시 이메일 도메인 기반 자동 분기:
- `.kr` / seoul / korea → seoul
- `.ae` / abudhabi / uae → abu_dhabi
- 그 외 → abu_dhabi (기본값) + admin에게 검토 Notification 발송

---

## 5. AI 자동화 기능

- **RFQ 자동 판별** (Claude Haiku) — 메일 수신 시 견적 가능성 점수화
- **답변 초안 자동 생성** — 확정된 RFQ는 회신 초안까지 자동 작성
- **중복 오더 감지** — 동일 `gmail_thread_id` 기반 자동 그룹핑 + 병합 UI
- **긴급 에스컬레이션** — 매일 07:30 마감 경과 + 미배정 오더에 admin/manager Notification (ISS-266)

---

## 6. 외부 연동

| 시스템 | 용도 | 연동 방식 |
|---|---|---|
| Gmail | 메일 수신/발송 | OAuth2 |
| eCount ERP | 품목/거래처/거래내역 마스터 | API 동기화 (매시 30/45분) |
| Google Chat | 납기/긴급 알림 | Incoming Webhook (재시도 큐 ISS-278) |
| SAP Ariba | 포털 문서 스크래핑 | Playwright 백그라운드 Job |

---

## 7. 문제 해결

- **PDF 한글 깨짐**: Docker 이미지 재빌드 시 자동 복구 (ISS-277 fonts-nanum 추가)
- **큰 파일 업로드 실패**: 50MB까지 허용. 그 이상은 ZIP 압축 또는 분할.
- **Gmail sync 안됨**: 상단 빨간 배너 → "다시 연결" → OAuth 재인증

자세한 문제 해결은 `docs/` 폴더의 각 기능별 리포트 참조.

---

## 8. 단축키

- `Cmd/Ctrl + K` — 전역 검색 (Command Palette)
- `Esc` — 드로어/모달 닫기

---

**지원**: admin@atozone.com
