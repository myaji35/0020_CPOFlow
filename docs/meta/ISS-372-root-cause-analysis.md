# ISS-372 [Meta] ISS-333 이슈 체인 근본 원인 분석

- **분석일**: 2026-07-28
- **분석 대상**: ISS-333 (`[RFP] ariba_login_capture 첨부파일 자동 필터링`) 파생 이슈 체인
- **원 이슈 상태**: AWAITING_USER (2026-05-02 생성, `confirm_category: BUDGET`)
- **결론**: **오탐(false positive)** — 핑퐁 아님. 게이트 fan-out을 핑퐁으로 오분류한 것. 해당 버그는 이후 이미 수정됨.

---

## 1. 체인 실측

ISS-333(P0 FIX_BUG, 2026-05-02 완료) 직계 자식 3건:

| ID | 타입 | 담당 | 상태 |
|---|---|---|---|
| ISS-336 | LINT_CHECK | code-quality | DONE |
| ISS-337 | RUN_TESTS | test-harness | DONE |
| ISS-338 | DOMAIN_ANALYZE | domain-analyst | AWAITING_USER |

세 건 모두 **서로 다른 타입, 각 1회씩**. 같은 작업이 에이전트 사이를 왕복한 흔적은 없다.

## 2. 왜 핑퐁으로 잡혔나 — 당시 meta-review.sh 패턴 4

당시 판정식:

```
len(children) >= 3  AND  len(agents) >= 2   →  핑퐁
```

`on_complete.sh`는 `FIX_BUG` 완료 시 **LINT_CHECK + RUN_TESTS + DOMAIN_ANALYZE를 정상 파생**시킨다(게이트 fan-out).
따라서 **모든 FIX_BUG/GENERATE_CODE는 완료되기만 하면 자식 3건 + 담당자 3명**이 되어,
설계대로 동작한 이슈일수록 100% 핑퐁으로 오탐되는 구조였다.

이것이 근본 원인이다. 버그는 ISS-333에 있지 않았고, **탐지기 쪽에 있었다.**

### 오탐 증거 — 같은 패턴의 반복 생성

`chain_length: 3`짜리 `[Meta] ... 이슈 체인 근본 원인 분석`이 총 7건 양산됨:

`ISS-064`(ISS-066) · `ISS-065`(ISS-035) · `ISS-184`(ISS-235) · `ISS-194`(ISS-237) ·
`ISS-195`(ISS-238) · `ISS-196`(ISS-239) · `ISS-372`(ISS-333) · `ISS-373`(ISS-344)

모두 동일한 형태 — **"정상 완료된 이슈 하나 + 게이트 3종"**. 진짜 핑퐁은 한 건도 없었다.

## 3. 현행 코드로 재판정 → 오탐 해소됨

현재 `meta-review.sh:179-201`에는 `GATE_FANOUT_TYPES` 화이트리스트와
`has_repeated_non_gate` 조건이 추가되어 있다:

```python
GATE_FANOUT_TYPES = {"LINT_CHECK", "RUN_TESTS", "DOMAIN_ANALYZE", "SCORE", ...}
non_gate_types = [t for t in child_types if t not in GATE_FANOUT_TYPES]
has_repeated_non_gate = len(set(non_gate_types)) < len(non_gate_types)
if len(agents) >= 2 and has_repeated_non_gate:   # ← 추가된 조건
```

ISS-333 체인을 이 코드로 재실행한 실측 결과:

```
types:    ['LINT_CHECK', 'RUN_TESTS', 'DOMAIN_ANALYZE']
non_gate: []                       → 반복 non-gate 없음
핑퐁 판정: False                   ← 현재 코드로는 생성되지 않는 이슈
```

**ISS-372는 현재 코드였다면 애초에 생성되지 않았을 이슈다.**

## 4. 2차 원인 — 비례성 결여 (아직 유효)

핑퐁 오탐과 별개로, ISS-333 체인은 **작업 규모 대비 검증 비용이 과했다.**

- ISS-333의 실체: 첨부파일 파일명·크기 기반 정규식 필터 1개 추가 (`estimated_hours: 1-2`)
- 그런데 파생된 것: LINT + TEST + **Opus 도메인분석** + SCORE + (형제 이슈로) **Opus CEO검토 + Opus Eng검토**

이 불균형은 당시 대표님이 직접 감지해 `requires_user_confirm: true / BUDGET` 으로 6건을 일괄 홀드시킨 것으로 registry에 남아 있다.
`confirm_reason`: *"Phase 0 단순 정제 작업 — 사후 CEO/Eng/SCORE 메타 검토 과잉"*

즉 **컨펌 게이트는 정상 작동했다.** 과잉 검증이 Opus 예산을 태우기 전에 멈췄다.
다만 그 판단이 **사람 손으로** 이뤄졌다는 것이 남은 갭이다.

### 미해결 갭: `estimated_hours` 기반 자동 비례 게이트 부재

`on_complete.sh`는 이슈의 크기(`estimated_hours`, diff 라인 수, 변경 파일 수)와 무관하게
동일한 게이트 세트를 파생시킨다. 1시간짜리 정규식 필터와 3일짜리 아키텍처 변경이 같은 검증을 받는다.

## 5. 조치

| # | 조치 | 상태 |
|---|---|---|
| 1 | 핑퐁 오탐 수정 (`GATE_FANOUT_TYPES` + `has_repeated_non_gate`) | ✅ 완료 (현행 코드에 반영됨) |
| 2 | ISS-372 자체 종결 — 오탐 유물이므로 재분석 불요 | ✅ 본 문서로 종결 |
| 3 | 동일 오탐 형제 ISS-373(ISS-344 체인)도 같은 사유로 종결 | ✅ 동시 처리 |
| 4 | `estimated_hours` 기반 게이트 비례 축소 | 신규 이슈로 분리 (P2) |

**Karpathy #3(Surgical) 준수**: 본 분석은 진단만 수행. 4번 항목은 별도 이슈로 분리하며 이번 diff에서 코드를 건드리지 않는다.

## 6. 학습 (knowledge 등재용)

> **자동 패턴 탐지기는 "설계된 정상 동작"을 먼저 화이트리스트에 넣어야 한다.**
> 그렇지 않으면 시스템이 정상 작동할수록 이상 신호가 늘어나, 탐지기가 자기 자신을 위한 작업을 양산한다.
> ISS-333 체인에서 실제로 발생한 일이 이것이다 — 정상 완료된 이슈 7건이 메타 분석 이슈 7건을 낳았다.
