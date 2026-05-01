# CPOFlow 배포 저변 전수 검사 통합 리포트
**작성**: 2026-04-24 · **대상**: https://cpoflow.ddtl.co.kr · **방식**: 2축 하네스(CHECK biz + journey + scenario) 병렬 디스패치

---

## 종합 점수

| 축 | 점수 | 등급 |
|---|---|---|
| **비즈니스 로직 무결성** | 30개 갭 (C8 / M14 / m8) | 🔴 CRITICAL |
| **사용자 여정 품질** | 26/40 | 🟡 개선 필요 |
| **도메인 시나리오 방어** | 10P / 9W / 6F (25중) | 🔴 CRITICAL |

**배포 준비 상태: 🔴 Production-Ready 아님** — CRITICAL 갭 4카테고리 즉시 차단 필요.

---

## 🔴 즉시 조치 필요 (CRITICAL, P0 9건)

### 1. Branch 격리 완전 붕괴 (5건)
`scoped_orders`를 써야 하는데 `Order.find()`를 쓰는 컨트롤러 11개. seoul 사용자가 abu_dhabi 오더 ID만 알면 다음 액션이 모두 가능:
- inbox의 번역/AI피드백/분류재설정/답변초안생성 (5개 액션)
- 전역 검색(/search)에서 Order/Client/Supplier/Employee/Project 전부
- thread_orders / preview_by_ref / price_history
- bulk / assignments / comments / tasks / order_quotes / order_links / pdf의 set_order
- admin#duplicate_orders#merge — manager가 두 branch 오더를 하나로 병합 가능(데이터 오염)

### 2. 권한 체계 부실 (3건)
- 신규 가입자 default role=**member** → 외부인이 가입 즉시 전체 발주 데이터 열람/생성
- `require_manager!`는 destroy 전용. **viewer가 PATCH /orders/:id/move 직접 호출 시 칸반 이동 성공**
- 파일 업로드 MIME 제약 없음 → **.exe, .bat, .sh 업로드 가능**

### 3. 배포 환경 설정 누락 (1건)
- `production.rb` SMTP 주석 + `default_url_options: host='example.com'` 그대로 → **비밀번호 재설정 메일 발송 불능**

---

## 🟡 주요 운영 갭 (MAJOR, P1 11건)

| 카테고리 | 갭 |
|---|---|
| UX 치명 | 드로어 "다음 단계" 버튼 `currentIdx=-1` 하드코딩 → 핵심 워크플로우 단절 |
| UX 치명 | viewer에게 Create 버튼 노출 (clients/employees index) |
| 상태머신 | 칸반 역행/건너뛰기 guard 없음 (`done → new_rfq` 역행 가능) |
| 자동화 | `OverdueEscalationJob` recurring.yml 미등록 → 납기초과 알림 미작동 |
| 데이터 | Report KPI가 :done 상태 미제외 → 수치 과다 집계 |
| 온보딩 | Google OAuth 가입 시 branch=abu_dhabi 하드코딩 |
| 동시성 | Order lock_version 없음 → 동시 편집 last-write-wins |
| 빈상태 | inbox 빈 상태에서 Gmail 미연결 CTA 없음 |
| 시그널 | Gmail 토큰 만료 경고가 Settings에만 — 대시보드/사이드바 무신호 |
| 네비게이션 | 직원 생성 후 비자/계약 추가 CTA 부재 |
| Primary Action | manager 대시보드 KPI가 하단 → 0.5초 룰 위반 |

---

## ⚪ MINOR (P2 7건)

- give_up 오더 복구 UI 없음 (API로만 가능)
- 칸반 split 시 OrderLink 역방향 미생성 → 이력 손실
- Nginx `client_max_body_size` 미설정 (Rails 25MB 전에 413)
- Docker 이미지 한글 폰트 누락 가능성 → PDF 깨짐
- Google Chat webhook 실패 시 재시도 큐 없음
- Claude Haiku 429 시 재시도 큐 없음
- 샘플 데이터/튜토리얼 부재 — 첫 로그인 가이드 없음

---

## 역할별 저니 매트릭스 요약

| 저니 | 판정 | 주 문제 |
|---|---|---|
| J1. 신규 member 첫 로그인 | 🔴 FAIL | 샘플 데이터 + 빈 칸반 가이드 부재 |
| J2. RFQ 이메일 → 칸반 전환 | 🟡 WARN | AI 분류 신뢰도 배지 부재 |
| J3. 오더 드로어 → 상태 이동 | 🔴 FAIL | 드로어 "다음 단계" 버튼 하드코딩 숨김 |
| J4. manager 팀 KPI 드릴다운 | 🟡 WARN | KPI 하단 배치, 0.5초 룰 위반 |
| J5. 경영 리포트 CSV | 🟢 PASS | — |
| J6. eCount 수동 동기화 → 병합 | 🔴 FAIL | admin#merge branch 격리 우회 (C-6) |
| J7. 직원 + 비자/계약 등록 | 🟡 WARN | 생성 후 다음 단계 CTA 부재 |
| J8. 발주처 + 담당자 + 오더 연결 | 🟢 PASS | — |
| J9. 칸반 상태 커스터마이징 | 🟢 PASS | — |
| J10. Gmail 연결 → 첫 sync | 🟡 WARN | 토큰 만료 시그널 부족 |

---

## 배포 영향도 Top 10 (즉시 수정 순서)

1. **inbox_controller 5개 액션 `scoped_orders.find` 전환** (5분) — Branch 격리 구멍 최다
2. **production.rb SMTP 활성화 + host=cpoflow.ddtl.co.kr** (즉시 효과) — 비밀번호 분실 복구 가능
3. **User default role=`viewer`로 변경** — 외부 가입자 데이터 노출 차단
4. **search_controller 전체 `scoped_orders` 적용** — 전역 검색 leak
5. **`require_member!` / `require_manager!` 액션 단위 재정비** — viewer가 move_status/update/attach 차단
6. **첨부 MIME allowlist 추가** (`.pdf .xlsx .jpg .png` 등) + `.exe/.bat/.sh` 차단
7. **recurring.yml에 OverdueEscalationJob 등록** — 자동 에스컬레이션 복구
8. **Order 모델 state_machine 또는 before_save guard** — 역행/건너뛰기 차단
9. **admin#duplicate_orders#merge에 scoped_orders 적용** — 데이터 오염 방지
10. **드로어 "다음 단계" 버튼 `currentIdx` 정상화** — 핵심 워크플로우 복구

---

## 하네스 처리 방향

- 27개 이슈가 `.claude/issue-db/registry.json`에 자동 등록됨 (ISS-254~ISS-280)
- P0 9건은 즉시 agent-harness 디스패치 대상
- "harness 시작" 명령으로 READY 이슈 순차 처리 가능

---

## 상세 리포트

- [`docs/biz-audit-2026-04-24.md`](biz-audit-2026-04-24.md) — 비즈니스 로직 갭 30건 상세 + 코드 증거
- [`docs/journey-audit-2026-04-24.md`](journey-audit-2026-04-24.md) — 4축 여정 품질 26/40 점수 + 축별 발견
- [`docs/scenario-audit-2026-04-24.md`](scenario-audit-2026-04-24.md) — 25개 도메인 시나리오 PASS/WARN/FAIL 판정

---

**결론**: 현재 배포는 기능적으로 동작하나 **Branch 격리 + 권한 + 배포 환경 설정** 3가지가 프로덕션 안전 기준 미달. CRITICAL 9건을 1~2일 내 수정 후 재감사 권장.
