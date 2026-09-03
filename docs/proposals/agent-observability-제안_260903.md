# CPOFlow 에이전트 관제(Observability) 도입 제안

> 2026-09-03 · 다른 세션(GH_Harness)에서 조사·작성 → 0020으로 전달
> 계기: 대표님이 LangSmith 실행추적 화면을 보시고 "각종 SaaS에 어떤 Agent가 관여해서
> 일을 하는지 궁금했다. 이런 화면을 볼 수 있는 줄 몰랐다"고 하심.

---

## 1. 현황 실측 (2026-09-03, `0020_CPOFlow` 기준)

### 이미 에이전트가 여럿 돌고 있다
자동 실행 잡 **23개**, LLM 실호출 **18곳**. 그런데 **한곳에서 볼 방법이 없다.**

**LLM을 호출하는 18개 지점**
```
jobs/quote_attachment_analyze_job.rb
jobs/rfp/analyze_attachments_job.rb
controllers/lab/rfq_auto_controller.rb
controllers/settings/api_keys_controller.rb
services/claude_token_resolver.rb
services/gmail/classification_result.rb
services/gmail/llm_rfq_analyzer_service.rb
services/gmail/rfq_reply_draft_service.rb
services/gmail/sonnet_escalator_service.rb
services/quote_item_extractor.rb            ← 토큰 기록 있음
services/review_json_sync_service.rb
services/rfp/attachment_classifier.rb
services/rfp/item_extractor.rb              ← 토큰 기록 있음
services/rfp/summary_report_service.rb
services/rfp/urgent_quote_email_drafter.rb
services/rfq_auto/analyzer.rb
services/rfq_auto/supplier_finder.rb
services/rfq_auto/vision_item_extractor.rb
```
(`views/` 3개는 안내 문구라 제외)

**cpo_agent 분석기 5종**: `auto_action` / `cost_saving_analyzer` /
`due_date_risk_analyzer` / `price_comparison_analyzer` / `supplier_risk_analyzer`

### 🔴 핵심 결함 — 비용 집계가 18곳 중 2곳뿐
토큰·비용을 기록하는 코드가 `quote_item_extractor.rb` 와 `rfp/item_extractor.rb`
**두 곳에만** 있다. 나머지 16곳은 세지 않는다.
→ **Claude API 요금이 나와도 어느 기능이 얼마를 썼는지 알 수 없다.**

### 이미 있는 자산 (기록 습관은 있으나 흩어져 있음)
`classification_log` / `agent_insight` / `ecount_sync_log` /
`import_log` / `sheets_sync_log`

---

## 2. 왜 필요한가 — 3건

**① 돈이 실제로 나간다.**
하네스 관제는 편의지만 여기는 상용 제품이고 API 비용이 실제 비용이다.
조달 업무라 처리량이 늘면 비용도 비례한다. 지금은 어디서 새는지 모른다.

**② 고객에게 판정 근거를 설명해야 한다.**
"AI가 이 RFQ를 왜 excluded 로 판정했나"에 답할 근거가 흩어져 있다.
조달은 금액이 걸린 판단이라 설명 가능성이 신뢰의 문제가 된다.
실행 추적이 있으면 판정 경로를 그대로 보여줄 수 있다.

**③ 무음 실패를 화면에서 잡는다.**
최근 커밋이 `fix(rfp): ISS-418 pdf_noise_title 무음 실패 제거 — rescue에 warn 로그 추가`.
전역 규칙 '실패경로 4문항'이 다루는 바로 그 문제인데, 지금은 사후 발견이다.
관제가 있으면 실패가 화면에 뜬다.

---

## 3. 화면 — 영상(LangSmith)에 준한다

대표님이 인상적이라 하신 것은 **관여도와 흐름을 타임라인으로 보는 것**이다.
막대 길이 = 소요시간, 굵기/수치 = 토큰·비용. 한 화면에서 "여기가 비용의 8할"이 보여야 한다.

```
주문 #1042   RFQ 접수 → 견적 → 발주                    총 8.4초 · $0.31
├─ email_sync            ▌            0.3s    —
├─ rfq_auto_analyze      ████         2.1s   $0.08
├─ quote_analyze         ██████████   4.8s   $0.19   ← 비용의 61%
└─ pricing_suggester     ██           1.2s   $0.04
```

**요건**
- 주문 1건을 클릭하면 관여한 에이전트가 타임라인으로 펼쳐질 것
- 각 단계의 입력·출력·판정근거를 열어볼 수 있을 것 (RFQ 판정 설명용)
- 실패한 단계는 시각적으로 구분될 것 (무음 실패 방지)
- 기간별 집계: 에이전트별 호출수·총비용·평균 소요·실패율

**LangSmith 는 쓰지 않는다.** LangGraph 전용이라 Rails 스택에 맞지 않는다.
데이터는 우리가 남기고 화면도 우리가 그린다.

---

## 4. 구현 방향

### 테이블 하나로 시작
```
agent_runs
  id, order_id(nullable), agent_name, kind(job/service/analyzer),
  started_at, finished_at, duration_ms,
  model, input_tokens, output_tokens, cost_usd,
  status(success/failure/skipped), error_message,
  input_digest, output_digest, parent_run_id(중첩 호출용)
```
18개 호출 지점이 여기에 한 줄씩 남기면 화면은 그리기만 하면 된다.

### 단계 (한 번에 다 하지 말 것)
| 단계 | 내용 | 비고 |
|---|---|---|
| 1 | `agent_runs` 테이블 + 기록 헬퍼 | 기존 코드 무영향 |
| 2 | **비용 큰 3~4곳부터** 계측 | quote_attachment_analyze, rfq_auto_analyze, rfp/item_extractor, vision_item_extractor |
| 3 | 주문별 타임라인 화면 1개 | 여기까지가 실질 값어치 |
| 4 | 나머지 호출 지점 확대 | 3단계 결과 보고 판단 |

### 주의
- 23G 규모 **운영 중인 앱**이다. 계측 코드가 기존 기능을 깨뜨리면 안 된다.
- 기록 실패가 본 기능을 막으면 안 된다 — 기록은 begin/rescue 로 감싸되 **무음 금지**(로그는 남긴다).
- 이미 있는 `classification_log` 등과 중복 기록하지 말 것. 통합할지 병존할지 먼저 판단.
- 입력·출력 원문을 통째로 저장하면 DB가 커진다. digest 또는 잘라 저장.

---

## 5. 하지 말 것
- LangSmith·외부 SaaS 도입 (스택 불일치 + 데이터 외부 유출)
- 18곳 전부 한 번에 계측 (회귀 위험)
- 화면부터 만들기 (데이터가 먼저)
