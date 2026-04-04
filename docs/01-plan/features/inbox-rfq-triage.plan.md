# Plan: inbox-rfq-triage

> 받은편지함 리팩토링 — 전체 메일함 + 견적성 메일 분리 + 멀티체크 Triage UI

## 1. 배경 및 문제점

### 현재 상태 (AS-IS)
```
Gmail 수신
  → EmailSyncJob (자동)
    → RfqDetectorService (AI 2단계 판정: Keyword 40% + LLM 60%)
      → rfq_confirmed → status: new_rfq → 칸반 New 블록 자동 진입
      → rfq_uncertain → Inbox "확인 필요" 탭 (사용자 개별 판정)
      → rfq_excluded → Inbox "일반 메일" (무시)
```

### 문제점
1. **AI 판정 신뢰도 불안정** — 오판(false positive/negative) 빈번, 견적이 아닌 메일이 칸반에 진입
2. **개별 판정 비효율** — uncertain 메일을 하나씩 열어서 "RFQ 맞음/아님" 클릭해야 함
3. **전체 메일 조망 불가** — 필터 기반 분리 뷰라 전체 흐름 파악 어려움
4. **학습 데이터 미체계화** — 피드백이 few-shot 5건만 활용, 체계적 학습 자료 축적 안 됨

### 대표님 기획 의도
- 전체 메일을 먼저 읽어온 뒤, **사용자가 직접 멀티체크로 견적성 메일을 분리**
- 견적성 메일로 판단한 내역은 **AI 학습 자료로 축적**
- **견적성 메일만** 칸반 보드 New 블록에 진입 가능

---

## 2. 목표 상태 (TO-BE)

### 새로운 플로우
```
Gmail 수신
  → EmailSyncJob (자동)
    → 모든 메일 → status: new_rfq, rfq_status: rfq_pending (신규 상태)
    → AI 판정은 백그라운드 "추천 점수"로만 활용 (자동 분류 안 함)

받은편지함 UI (단일 뷰):
  ┌─────────────────────────────────────────────────┐
  │ 필터: [검색...] [발신자 ▾] [기간 ▾]              │
  │                                                   │
  │ ☐ 전체선택   3건 선택됨                           │
  │ [🗑 삭제]  [📋 견적으로 이동]                     │
  │                                                   │
  │ ☑ ★★★ 메일 A — RFQ for Waterproofing            │
  │ ☑ ★★☆ 메일 B — Quotation Request                │
  │ ☑ ★☆☆ 메일 C — 소화기 견적 요청                  │
  │ ☐  —  메일 D — Security Alert                    │
  │ ☐  —  메일 E — [PR] Merged #123                  │
  └─────────────────────────────────────────────────┘

사용자 워크플로우:
  1. 키워드 필터로 관련 메일 추림
  2. 멀티체크로 대상 선택
  3. [삭제] → 비견적 메일 제거 (정답 데이터 기록)
     [견적으로 이동] → 칸반 New(신규) 블록 직행 (정답 데이터 기록)
```

---

## 3. 핵심 변경사항

### 3.1 rfq_status Enum 변경

| 기존 | 신규 | 의미 |
|------|------|------|
| rfq_confirmed (0) | rfq_triage (0) | 견적성 메일로 분류됨 (사용자 확정) |
| rfq_uncertain (1) | rfq_pending (1) | 미분류 (전체 메일함 대기) |
| rfq_excluded (2) | rfq_excluded (2) | 사용자가 명시적 제외 |
| — | rfq_archived (3) | 처리 완료 (칸반 이동 후) |

> **주의**: 기존 DB 정수값 유지. `rfq_confirmed(0)` → `rfq_triage(0)`로 이름만 변경. 마이그레이션 불필요.

### 3.2 칸반 진입 게이트 변경

```ruby
# AS-IS: AI가 confirmed하면 바로 칸반 진입
# TO-BE: 사용자가 "견적성 메일"로 확정 + "칸반 이동" 클릭해야 진입

# 칸반 표시 조건 변경
scope :kanban_visible, -> {
  where(rfq_status: :rfq_triage)      # 견적성 확정된 것만
    .where.not(status: :new_rfq)       # 칸반으로 이동된 것만
    .or(where.not(status: :new_rfq))   # 기존 칸반 카드 유지
}
```

### 3.3 AI 판정 역할 변경

```
AS-IS: AI가 자동 분류 (confirmed/uncertain/excluded)
TO-BE: AI는 "추천 점수"만 제공, 최종 분류는 사용자
  - rfq_score: 0~100 (기존 유지)
  - rfq_confidence: high/medium/low (기존 유지)
  - UI에 ★ 아이콘으로 추천 강도 표시
  - 모든 메일은 rfq_pending(1)으로 시작
```

---

## 4. UI 기획

### 4.1 받은편지함 — 단일 뷰 (필터 + 멀티체크 + 액션)

**핵심 UX**: 탭 분리 없이 **하나의 메일 리스트**에서 키워드 필터 → 멀티체크 → 삭제 또는 견적이동

```
┌─────────────────────────────────────────────────────────────┐
│ 받은 편지함 — AtoZ2010 Inc.           [동기화] [+ 신규 발주] │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ ┌── 필터 바 ──────────────────────────────────────────────┐ │
│ │ [검색...]  [발신자 ▾]  [기간 ▾]  [AI추천순 ▾]          │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌── 액션 바 (선택 시 노출) ──────────────────────────────┐ │
│ │ ☐ 전체선택   3건 선택됨                                  │ │
│ │ [🗑 삭제]  [📋 견적으로 이동 ▸]                          │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌── 메일 리스트 ─────────────────────────────────────────┐  │
│ │ ☑ ★★★  ENEC — RFQ for Waterproofing...   Apr 3       │  │
│ │ ☑ ★★☆  SOOSAN — Quotation Request...     Apr 2       │  │
│ │ ☑ ★☆☆  KEPCO — BNPP 소화기 견적 요청     Apr 1       │  │
│ │ ☐  —   Google — Security Alert...         Apr 1       │  │
│ │ ☐  —   GitHub — [PR] Merged #123...       Mar 31      │  │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌── 메일 본문 (우측 패널) ───────────────────────────────┐  │
│ │ [원문] [번역] [답변초안]                                │  │
│ │                                                         │  │
│ │ 클릭한 메일의 본문 표시                                  │  │
│ └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 사용자 워크플로우 (3단계)

```
Step 1: 키워드 필터
  검색창에 "RFQ", "quotation", "견적" 등 입력
  → 관련 메일만 표시 (나머지 숨김)

Step 2: 멀티체크
  ☐ 전체선택 또는 개별 체크
  Shift+클릭으로 범위 선택 지원

Step 3: 액션 실행
  [🗑 삭제] → rfq_excluded 처리 (리스트에서 제거)
             + RfqFeedback(verdict: "rejected") 기록
  [📋 견적으로 이동] → 칸반 New(신규) 블록으로 직행
                      + RfqFeedback(verdict: "confirmed") 기록
                      + 정답 데이터(Ground Truth) 축적
```

### 4.3 액션 바 동작

| 상태 | 액션 바 | 동작 |
|------|---------|------|
| 체크 0건 | 숨김 | — |
| 체크 1건+ | 노출 | 전체선택 / N건 선택됨 / 삭제 / 견적이동 |
| 삭제 클릭 | 확인 다이얼로그 | "N건을 삭제하시겠습니까?" → rfq_excluded |
| 견적이동 클릭 | 즉시 실행 | status: make_quo + rfq_triage → 칸반 New 진입 |

### 4.4 삭제된 메일 복구

```
필터 바 우측에 [🗑 휴지통 (N)] 링크
  → rfq_excluded 메일 목록 표시
  → 멀티체크 → [복원] → rfq_pending 복귀
```

---

## 5. 데이터 플로우

### 5.1 메일 수신 → 분류 → 칸반

```
Gmail 수신
  │
  ▼
EmailSyncJob
  │ RfqDetectorService → rfq_score, rfq_confidence 계산 (추천용)
  │ 모든 메일 → rfq_status: rfq_pending (미분류)
  │ status: new_rfq
  │
  ▼
받은편지함 (단일 뷰)
  │ 키워드 필터로 관련 메일 추림
  │ 멀티체크 선택
  │
  ├─ [🗑 삭제] → rfq_excluded + RfqFeedback("rejected") 기록
  │
  └─ [📋 견적으로 이동] → status: make_quo + rfq_triage
     │                    + RfqFeedback("confirmed") 기록
     ▼
칸반 보드 — New(신규) 블록
```

### 5.2 AI 자동 판정 테스트용 정답 데이터(Ground Truth) 수집

**목적**: 사용자가 수동 분류한 결과를 "정답지"로 축적하여, 향후 AI 자동 판정의 정확도를 측정하고 임계값을 튜닝하기 위한 테스트 자료로 활용.

```
사용자 액션                    → 기록되는 정답 데이터
───────────────────────────────────────────────────────
전체→견적성 이동              → RfqFeedback(verdict: "confirmed")
                                + sender_domain, subject_pattern
                                + ai_score (당시 AI 판정 점수 기록)
전체→제외 처리                → RfqFeedback(verdict: "rejected")
                                + sender_domain, subject_pattern
                                + ai_score
견적성→되돌리기               → RfqFeedback(verdict: "reverted")
                                + 기존 feedback 취소

정답 데이터 활용 로드맵:
Phase 1 (현재): 수동 분류 → 정답 데이터 축적
Phase 2 (데이터 충분 시): AI 판정 vs 정답 비교 → 정확도 리포트
  - Precision: AI가 견적이라 한 것 중 실제 견적 비율
  - Recall: 실제 견적 중 AI가 맞춘 비율
  - F1 Score: 종합 정확도
Phase 3 (정확도 90%+ 달성 시): AI 자동 견적 분류 재활성화 근거
  - 임계값 튜닝 (현재 hybrid >= 70 → 데이터 기반 최적값)
  - 도메인별 자동 확정 규칙 생성

학습 통계 대시보드:
- 총 정답 데이터 N건
- AI 판정 일치율 (AI가 높은 점수 준 것 중 사용자도 견적 확정한 비율)
- 도메인별 견적/비견적 분포
- 정확도 추이 그래프 (주간/월간)
```

---

## 6. API 엔드포인트

### 6.1 신규 엔드포인트

| Method | Path | 기능 |
|--------|------|------|
| POST | `/inbox/bulk_delete` | 멀티체크 → 삭제 (rfq_excluded) + 정답 데이터 기록 |
| POST | `/inbox/bulk_to_kanban` | 멀티체크 → 견적으로 이동 (칸반 New) + 정답 데이터 기록 |
| POST | `/inbox/bulk_restore` | 휴지통 → 복원 (rfq_pending 복귀) |
| GET | `/inbox/learning_stats` | AI 정답 데이터 통계 (AJAX) |

### 6.2 기존 엔드포인트 변경

| 엔드포인트 | 변경 |
|-----------|------|
| `GET /inbox` | `filter` 파라미터에 `trash` 추가 (휴지통 보기) |
| `POST /inbox/:id/convert` | 제거 (bulk_to_kanban으로 대체) |

---

## 7. 구현 단계

### Phase A: DB & 모델 변경 (Day 1)
1. rfq_status enum 이름 변경 (rfq_confirmed → rfq_triage, rfq_uncertain → rfq_pending)
2. rfq_archived(3) 추가 마이그레이션
3. 기존 데이터 마이그레이션 (confirmed → triage, uncertain → pending)
4. Order 모델 scope 추가 (pending, triaged, kanban_eligible)
5. RfqFeedback에 "reverted" verdict 지원

### Phase B: EmailSyncJob 변경 (Day 1)
1. 모든 신규 메일 → rfq_status: rfq_pending으로 통일
2. AI 판정 결과는 rfq_score/rfq_confidence에만 저장 (rfq_status 미변경)
3. 기존 auto-confirmed 로직 제거

### Phase C: Inbox UI 리팩토링 (Day 2-3)
1. 단일 뷰 레이아웃 (필터 바 + 메일 리스트 + 본문 패널)
2. 키워드 필터 (검색 + 발신자 + 기간 + AI추천순)
3. 멀티체크 UI (체크박스 + 전체선택 + Shift 범위선택)
4. 액션 바 (선택 시 노출: 삭제 / 견적으로 이동)
5. AI 추천 점수 표시 (★ 아이콘)
6. 휴지통 링크 (삭제된 메일 복원)
7. turbo:load 기반 JS 초기화

### Phase D: Bulk API 구현 (Day 3)
1. bulk_delete (삭제 → rfq_excluded)
2. bulk_to_kanban (견적 이동 → make_quo + rfq_triage)
3. bulk_restore (휴지통 복원 → rfq_pending)
4. 각 액션마다 RfqFeedback + ai_score 자동 기록

### Phase E: AI 학습 강화 (Day 4)
1. Few-shot 예시 20건으로 확대
2. 학습 통계 API (일치율, 정확도 추이)
3. 견적성 메일 탭 하단 학습 통계 표시

### Phase F: 칸반 연동 정리 (Day 4)
1. 칸반 New 블록 → rfq_triage + status != new_rfq 조건
2. 기존 convert_to_order → rfq_status 검증 추가

---

## 8. 리스크 및 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| 기존 rfq_confirmed 데이터 호환 | 기존 칸반 카드 영향 | 마이그레이션으로 자동 전환 |
| 멀티체크 대량 처리 성능 | 500건+ 일괄 처리 | 배치 처리 + Turbo Stream |
| AI 점수 없는 기존 메일 | 추천 정렬 불가 | rfq_score NULL → 0점 취급 |
| 사용자 실수 (잘못된 분류) | 견적 누락 | "되돌리기" 기능으로 복구 |

---

## 9. 성공 지표

- [ ] 전체 메일함에서 모든 수신 메일 조회 가능
- [ ] 멀티체크로 견적성 메일 일괄 이동 가능
- [ ] 견적성 메일에서만 칸반 이동 가능
- [ ] AI 추천 점수(★) 표시 정상
- [ ] 되돌리기 기능으로 오분류 복구 가능
- [ ] RfqFeedback에 모든 사용자 판정 기록
- [ ] 학습 통계 표시 (일치율, 정확도)
- [ ] 기존 칸반 카드 영향 없음
