# ISS-422 [Agent관제] 에이전트 실행 모니터링 단일 페이지 — 기획

> 2026-09-03 · plan-harness:product (Fable 5.1) · 입력: `docs/proposals/agent-observability-제안_260903.md`
> 검증 방법: 제안서 주장을 코드(`app/`)·스키마(`db/schema.rb`)·개발DB(`storage/development.sqlite3`)·로그·`config/recurring.yml`로 직접 대조.

## 판정: 된다
`agent_runs` 1개 테이블 신설(C안) + `/admin/agent_runs` 단일 페이지. 기존 `classification_logs`는 건드리지 않고 미러+백필로 병합한다.
**전제**: 자동 Gmail sync가 2026-05-30 비용 정지로 꺼져 있어(§1-④) 데이터 유입 재개는 대표님 결정(T2 BUDGET, 이슈 422-F)이다. 재개 전에도 백필 + 수동 실행으로 페이지는 뜬다.

---

## ① 실측 대조표 — 제안서 주장 vs 실제

| # | 제안서 주장 | 실측 (근거 파일) | 판정 / 기획 반영 |
|---|---|---|---|
| 1 | 비용 집계가 18곳 중 **2곳뿐** | 토큰·비용 코드는 **12개 파일**. 그러나 "산출"과 "저장"이 다르다. **저장되는 곳은 3테이블뿐**: `classification_logs.cost_usd`(orchestrator), `attachment_quote_analyses.cost_usd`(QuoteAttachmentAnalyzeJob), `rfq_auto_analyses.cost_usd`(RfqAuto::Analyzer). 산출만 하고 버리는 곳: `Rfp::ItemExtractor`(`_cost_usd` 반환 → `Rfp::AnalyzeAttachmentsJob`가 미저장), `Rfp::SummaryReportService`(logger.info만). 산출조차 없는 곳: `Gmail::LlmRfqAnalyzerService`(Stage 2 Haiku), `RfqReplyDraftService`, `Rfp::AttachmentClassifier`, `Rfp::UrgentQuoteEmailDrafter` | 틀림. 결손의 정확한 위치는 **"Stage 2 비용 0 고정 버그" + "Rfp 파이프라인 미저장"** 두 가지 → 이슈 422-B, 422-C |
| 2 | `agent_runs` 테이블 **신설 필요** | `classification_logs`(order_id, model, cost_usd 10,6, latency_ms, verdict, stage_reached, reason …)가 이미 있음. 단, 분류 **도메인 전용**이며 소비자 5곳이 `ClassificationLog.v2` 스코프에 의존: `Gmail::CostGuard.today_cost`(일 $0.35 게이트), `ClassifyV2Day3Gate`, `ShadowFnDetectorJob`, `Admin::RfqStatsController#load_classify_v2_metrics`, `Gmail::EmailToOrderService`(order_id 백링크 `update_all`) | 반은 맞음. 범용 로그로 **확장하면 CostGuard가 타 에이전트 비용까지 합산해 분류를 오차단**한다 → B안 기각, **C안**(§③) |
| 3 | LLM 호출 18곳 / 잡 23개 | `claude-\|anthropic\|ClaudeTokenResolver` 참조 파일 **16개**. 그중 실제 API 호출 서비스 **10개**(llm_rfq_analyzer, sonnet_escalator, rfq_reply_draft, quote_item_extractor, rfp/attachment_classifier, rfp/item_extractor, rfp/summary_report, rfp/urgent_quote_email_drafter, rfq_auto/vision_item_extractor, settings/api_keys 검증). 잡은 `app/jobs` 26개 + `rfp/` 1개 | 수치 정정. 계측 대상은 "파일 16개"가 아니라 **"실행 경로 6개"**(§③-3) |
| 4 | (부모 실측) 테이블은 있는데 데이터가 안 쌓인다 → 배선 끊김 | **배선은 살아 있다**: `EmailSyncJob` L108~124 → `CostGuard.exceeded?` → `ClassificationOrchestrator#classify` → `log_and_return` → `ClassificationLog.create!`. 멈춘 원인은 두 가지. (a) **`config/recurring.yml` 2026-05-30 "배포 리소스/LLM 비용 정지 — 자동 Gmail sync 비활성화"로 `gmail_sync_all`이 주석 처리됨** → 운영에서 신규 분류 이벤트 자체가 없다(inbox 수동 Sync 버튼만 남음). (b) 개발DB는 sync를 돌린 적이 없다(orders 6건, `development.log`에 EmailSyncJob 0회). `attachment_quote_analyses`·`rfq_auto_analyses` 0행도 같은 이유(수동 트리거 전용 기능을 개발DB에서 안 씀) | **"배선 끊김"이 아니라 "수도꼭지 잠금"**. 새 테이블을 만들어도 sync를 켜지 않으면 똑같이 빈다 → 이슈 422-F(유입 재개 결정)가 기획에 필수. ⚠ 운영DB 행수는 미실측(부모 확인 항목 §⑤) |
| 5 | 데이터가 먼저, **화면부터 만들기 금지** | 대표님 목표는 "보는 것". 기존 3테이블 백필이면 운영 이력(있다면)이 첫날부터 보이고, 없어도 빈 상태 자체가 "수도꼭지 상태"라는 정보다 | 수정. **테이블(4h) 직후 페이지(6h)** 를 올린다. 계측 확대는 페이지를 보며 판단 |
| 6 | 화면 목업: 주문별 막대 타임라인 | 채택. 단, LangSmith의 핵심인 **중첩(parent→child)** 과 **실패 시각화**가 목업에 없어 추가. Rails/Hotwire로 차트 라이브러리 없이 Tailwind div 막대로 구현 가능 | 개선 채택(§②-S4) |
| 7 | cpo_agent 분석기 5종도 "에이전트" | `app/services/cpo_agent/*`·`AgentInsightJob`은 LLM 미호출(규칙 기반). 비용 0 | 1차 범위 제외, 2차(422-G)에서 `kind=job`으로 선택 계측 |
| 8 | 부수 발견 | `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`가 **런타임에 `.claude/issue-db/registry.json`을 직접 쓴다**(운영 앱이 하네스 파일을 수정). 관제 테이블이 생기면 이 카운터의 존재 이유가 사라진다 | 본 이슈 범위 밖. 별도 REFACTOR 후보로 부모에 보고만 |

**비용 계산 로직 현황(계측 설계 근거)**
- Sonnet Stage 3: `SonnetEscalatorService#compute_cost` — cache_read 포함 정확 산출 ✔
- Vision(Sonnet 4.6): `QuoteItemExtractor` / `RfqAuto::VisionItemExtractor` — INPUT/OUTPUT_PER_MTOK 상수 ✔
- `Rfp::ItemExtractor` L206~215 / `Rfp::SummaryReportService` L98 — 산출 ✔ 저장 ✘
- **Haiku Stage 2 `LlmRfqAnalyzerService#parse_response` — usage 미파싱, cost 키 없음 → `normalize_haiku`가 `haiku_hash[:cost_usd].to_f` = 0.0** → `classification_logs.cost_usd` Stage 2 행은 전부 0 → **CostGuard가 Haiku 비용을 못 본다**(Sonnet 에스컬레이션분만 집계). 개발DB의 "cost 합계 $0"은 rule-only 2행이라 이 버그의 증거는 아니지만, 코드상 확정.

---

## ② 단일 페이지 화면 설계 — `/admin/agent_runs`

### 기본 사양
| 항목 | 결정 |
|---|---|
| 라우트 | `namespace :admin { resources :agent_runs, only: %i[index show] do collection { get "orders/:order_id", action: :order_timeline, as: :order_timeline } end }` → `GET /admin/agent_runs`(페이지), `GET /admin/agent_runs/:id`(상세 Turbo Frame), `GET /admin/agent_runs/orders/:order_id`(타임라인 Turbo Frame). **URL은 하나**, 나머지 둘은 같은 페이지 안의 프레임 요청 |
| 컨트롤러 | `Admin::AgentRunsController` — `before_action :require_admin!` |
| 권한 | **admin 전용**. 근거: LLM 비용·프롬프트 요약·오류 원문은 운영 정보. 사이드바 배치는 `_sidebar.html.erb` L135 "admin 페르소나 전용" 블록(메뉴 권한·피드백 관리 옆), 아이콘 `lni lni-pulse`, 라벨 `t("nav.agent_runs", default: "Agent 관제")` |
| 필터(쿼리 파라미터) | `window` = `24h`/`7d`(기본)/`30d`, `agent`(agent_name), `status`(success/failure/skipped), `q`(주문 id 또는 제목) |
| 언어 | 개발 한국어 UI, `t(..., default: "한국어")` 패턴(사이드바와 동일). 운영 영어는 `en.yml` 키 추가 |
| 디자인 토큰 | **`brand-dna.json`(_status active, 2026-04-21) 우선**: hero `#166c72`(Deep Teal) = 주요 CTA·활성 필터, `shell_bg #1E3A5F`는 사이드바만, 배지는 solid 배경+흰 글자, radius ≤ 7px, 13px dense, Line/Feather outline 아이콘. ⚠ 부모 지시의 Primary `#1E3A5F`/Accent `#00A1E0`는 brand-dna anti_patterns("SLDS navy → Deep Teal 전환")와 충돌 → brand-dna를 따른다. 기존 `rfq_stats` 뷰(#16325C/#00A1E0)는 전환 전 잔재이므로 모방하지 않는다 |
| 주요 CTA(MUST_EXIST) | 헤더 우측 `[Gmail 동기화 실행]` → 기존 `POST /inbox/sync`(`inbox_sync_path`, JSON) 재사용 → 토스트 "N개 계정 큐 등록". 이 버튼이 곧 데이터 유입 장치라 화면의 첫 행동이 된다 |
| 새로고침 | 수동 버튼 + 페이지 헤더에 "마지막 집계 HH:MM". 실시간 스트림은 1차 범위 밖(§⑤ 더 하면 좋은 것) |

### 섹션 구성 (위→아래, 한 화면 세로 스크롤)

**S1 헤더바** — 제목 "Agent 관제", 부제 "어떤 에이전트가 어느 주문에 관여해 얼마를 썼는지", 기간 세그먼트(24h/7d/30d), 에이전트 select, 상태 select, 주문 검색, `[Gmail 동기화 실행]`(hero), `[새로고침]`.

**S2 KPI 스트립(5타일)**
| 타일 | 값 | 출처 |
|---|---|---|
| 실행 수 | `AgentRun.in_window.count` | agent_runs |
| 총 비용 | `sum(:cost_usd)` USD 4자리 | agent_runs |
| 실패율 | failure / (success+failure) % — 0건이면 "—" | agent_runs.status |
| 평균 소요 | `average(:duration_ms)` → 초 | agent_runs |
| 오늘 분류 예산 | `Gmail::CostGuard.status` 게이지 + OK/WARN(≥80%)/BLOCKED 배지 | classification_logs(기존 로직 재사용, 수정 없음) |

**S3 에이전트별 집계(표)** — 행 = `agent_name`. 컬럼: 에이전트 · kind · 실행수 · 총비용 · **비용 비중 막대(%)** · 평균 소요 · 실패율 · 마지막 실행. 비용 desc 정렬, 1행에 "비용의 N%" 강조 배지(제안서 "여기가 비용의 8할"). 출처: `AgentRun.in_window.group(:agent_name)` 집계 4쿼리(count/sum/avg/failure count).

**S4 주문별 타임라인(LangSmith 대응 핵심)** — 기간 내 관여 주문 최근 20건. 카드 헤더: `#id · Order#display_subject · 에이전트 N개 · 총 소요 · 총 비용 · [실패 n]`. 헤더 클릭 → `<turbo-frame id="order-timeline-{id}" src=order_timeline_path loading="lazy">`로 막대 목록 로드:
```
#1042  RFQ 접수 → 첨부분석                          총 8.4s · $0.312 · 실패 1
 gmail.classify            ▌                 0.3s   $0.000  success  haiku-4.5
 rfp.analyze_attachments   ██████████████    6.9s   $0.271  success
   └ rfp.item_extract      ██████████        4.8s   $0.190  success  claude-sonnet-4-6
   └ rfp.summary_report    ████              2.0s   $0.081  success
 gmail.reply_draft         ██                1.2s   —       failure  ← "AnthropicCreditError: …"
```
- 막대 폭 = `duration_ms / 해당 주문 max_duration_ms * 100%`(최소 2%). 색: success `ok #2e9856`, failure `danger #c84431`, skipped `text_secondary`, running 줄무늬.
- `parent_run_id` 있으면 1단 들여쓰기(`└`). 행 클릭 → S6 상세 프레임 갱신.
- 차트 라이브러리 없음. Tailwind CDN div + inline `style="width:N%"`.

**S5 최근 실행 피드(표)** — 50건/페이지(`pagy` 9.0 이미 Gemfile). 컬럼: 시각 · 에이전트 · 주문(링크: 칸반 드로어) · 모델 · 소요 · 비용 · 상태 배지 · 오류 요약(60자). 행 클릭 → S6.

**S6 실행 상세 패널** — 우측 고정 `<turbo-frame id="agent-run-detail">`(빈 상태: "실행을 선택하세요"). 내용: 기본(agent/kind/status/model) · 타이밍(started/finished/duration) · 토큰/비용(input/output/cost) · **`meta` JSON 보기 좋게**(판정근거 reason/verdict/stage/추출 품목 수 등 — 제안서 요건 "판정 근거 열어보기") · `error_message` 전문 · 원본 레코드 링크(`source_type/source_id` → ClassificationLog / AttachmentQuoteAnalysis / RfqAutoAnalysis) · 주문 드로어 링크.

### 빈 상태(데이터 없음) — 세 층
| 상황 | 표시 |
|---|---|
| **agent_runs 전체 0행** | S3~S5 대신 안내 카드 1장: "기록된 에이전트 실행이 없습니다. 자동 Gmail 동기화는 2026-05-30 비용 정지로 꺼져 있습니다(`config/recurring.yml`)." + 행동 3개: `[Gmail 동기화 실행]`(hero) / `[칸반에서 첨부 분석 실행]`(kanban 링크) / `[LAB RFQ Auto]`. S2의 CostGuard 게이지는 그대로 표시(분류 예산 상태는 데이터와 무관하게 유효) |
| 기간 내 0행(전체는 있음) | 각 섹션 자리에 "최근 {window} 실행 없음 — [30일로 넓히기]" |
| 특정 섹션만 비어 있음 (예: 주문 미연결 실행만 있음) | S4: "주문에 연결된 실행이 없습니다(주문 없이 실행된 N건은 아래 피드에 표시)" |

### 성능·안전
- 모든 조회는 `agent_runs` 인덱스(`created_at`, `[agent_name, created_at]`, `[order_id, started_at]`, `status`)로 처리. window 상한 30일.
- S4는 주문당 lazy 프레임 → 초기 렌더는 집계 쿼리 6~8개로 고정. `includes(:order)`로 N+1 차단.
- 관제 페이지는 **읽기 전용**. 쓰기는 `[Gmail 동기화 실행]`(기존 엔드포인트)뿐.

---

## ③ 데이터 모델 판정 — **C안 (agent_runs 신설 + 기존 3테이블을 미러·백필로 병합)**

### 왜 A(신설만)·B(classification_logs 확장)가 아닌가
| 안 | 회귀 위험(23G 운영 앱) | 결정적 결함 |
|---|---|---|
| A 신설만 | 낮음 | 운영에 이미 쌓인 분류·첨부분석·RFQ Auto 이력이 화면에 안 보인다. 진실 소스가 둘(classification_logs vs agent_runs)로 갈린다 |
| B 확장 | **높음** — `ClassificationLog.v2` 스코프 소비자 5곳(CostGuard·Day3Gate·ShadowFnDetector·RfqStats·EmailToOrder 백링크) 전부 손대야 함 | `CostGuard.today_cost = ClassificationLog.v2.sum(:cost_usd)`에 첨부분석(Sonnet vision, 건당 $0.02~)이 섞이면 **일 $0.35 게이트가 오발동해 RFQ 분류를 꺼버린다**. verdict/is_rfq/would_exclude 컬럼은 타 에이전트에 무의미 |
| **C** | **낮음** — 기존 테이블·쿼리 무수정. 추가는 write 3곳 각 1~3줄(rescue 안) | 없음. 도메인 로그(왜 excluded인가)는 기존 자리에, 관제 로그(누가 언제 얼마)는 agent_runs에. `source_type/source_id`로 서로 연결 |

### 스키마 (`create_table :agent_runs`)
```ruby
t.references :order, null: true                       # 주문 미연결 실행 허용(pre-create 분류 등)
t.string   :agent_name,  null: false                  # "gmail.classify" "quote.attachment_analyze" "rfp.analyze_attachments" "rfp.item_extract" "rfp.summary_report" "rfq_auto.analyze" …
t.string   :kind,        null: false, default: "service"   # job | service | stage
t.string   :status,      null: false, default: "running"   # running | success | failure | skipped
t.datetime :started_at,  null: false
t.datetime :finished_at
t.integer  :duration_ms
t.string   :model
t.integer  :input_tokens, :output_tokens
t.decimal  :cost_usd, precision: 10, scale: 6, default: 0
t.text     :error_message                             # 1,000자 절단
t.text     :meta                                      # JSON ≤ 4KB. 판정근거·요약만. 입출력 원문 저장 금지(제안서 §4 주의 동일)
t.string   :source_type; t.bigint :source_id          # 도메인 레코드 포인터
t.integer  :parent_run_id                             # 중첩 호출
t.timestamps
# index: created_at / [agent_name, created_at] / [order_id, started_at] / status / parent_run_id / [source_type, source_id] UNIQUE(백필 멱등)
```
제안서의 `input_digest/output_digest`는 제외(사용처 없음 — Karpathy #2). 필요 시 meta에 넣는다.

### 기록 헬퍼 `AgentRun.track` — 실패경로 4문항 답
```ruby
# 블록형
AgentRun.track(agent: "rfp.item_extract", order: order, kind: "service", parent: parent_run) do |run|
  result = Rfp::ItemExtractor.call(text)
  run.note(cost_usd: result["_cost_usd"], input_tokens: result["_input_tokens"],
           output_tokens: result["_output_tokens"], model: Rfp::ItemExtractor::MODEL,
           meta: { items: result["items"]&.size })
  result
end
# 수동형 (잡처럼 자체 rescue가 있는 곳)
run = AgentRun.start!(agent:, order:, source:)  …  run.finish!(cost_usd: …) / run.fail!(error)
```
| 문항 | 답 |
|---|---|
| 1 가짜 채우기 | 기록 실패 시 값을 지어내지 않는다. `start!` 실패 → `NullRun`(no-op) 반환, 본 기능 계속. 비용 미산출 경로(2차 계측 전)는 `cost_usd NULL`로 남기고 화면에 "미집계" 표시 — 0으로 표시하지 않는다 |
| 2 무음 실패 | 모든 DB 쓰기는 `rescue StandardError => e; Rails.logger.warn("[AgentRun] write failed agent=… #{e.class}: #{e.message}")`. 절대 raise 하지 않음 |
| 3 사용자 인지 | 블록 안 예외는 `fail!` 기록 후 **그대로 re-raise** → 호출자 기존 rescue·폴백 태스크 로직 무변경. 화면 S4/S5에 failure 빨강 + error_message |
| 4 금전 정합 | 관제는 돈을 움직이지 않는다. CostGuard 게이트는 기존 classification_logs 그대로(무변경) |

### 1차 계측 대상 6경로 (이슈 422-C) — "가장 자주·비싸게 도는 곳" 판정 근거
| 우선 | 경로 | 빈도/비용 근거 | 방식 |
|---|---|---|---|
| 1 | `Gmail::ClassificationOrchestrator#log_and_return` | 메일 1통당 1회. 유입 재개 시 최다 빈도. Haiku+Sonnet | **미러**: `ClassificationLog.create!` 직후 `AgentRun` 1행(agent `gmail.classify`, source=log, meta {verdict, stage_reached, reason, confidence}; reason이 `safety_fallback`이면 failure). `EmailToOrderService`의 order_id 백링크 `update_all`에 agent_runs 1줄 추가 |
| 2 | `Rfp::AnalyzeAttachmentsJob` | 칸반에서 트리거, **건당 최고가**(ItemExtractor Sonnet 장문 + Summary) — 현재 비용 전량 유실 | 부모 run `rfp.analyze_attachments`(kind job) + 자식 `rfp.item_extract`(`_cost_usd/_input_tokens/_output_tokens` 채움) + 자식 `rfp.summary_report`(`report[:cost_usd]`) |
| 3 | `QuoteAttachmentAnalyzeJob` | 첨부 1개당 Sonnet vision | **미러**: `aqa.update!(completed/failed)` 직후 agent_runs 1행(source=aqa) |
| 4 | `RfqAuto::Analyzer#call` | LAB, 6단계 합산 비용 | **미러**: `@analysis.update!(completed/failed)` 직후 1행(source=analysis). step 자식 행은 2차 |

(Stage 2/3를 `gmail.classify`의 자식 stage 행으로 나누는 것, `gmail.reply_draft`, `rfp.attachment_classify`, `rfp.urgent_draft`, vision 자식 행은 **2차 422-G** — 이 4곳은 usage 파싱 코드부터 없어 산출 로직 추가가 필요하므로 회귀 범위를 1차와 분리)

### 백필 `bin/rails agent_runs:backfill` (이슈 422-A에 포함)
| 원본 | 매핑 |
|---|---|
| `classification_logs` | agent `gmail.classify`, started_at = created_at − latency_ms, status = reason LIKE 'safety_fallback%' ? failure : success, model/cost/latency 그대로, meta {verdict, stage_reached, reason, confidence, would_exclude} |
| `attachment_quote_analyses` (status ∈ completed/failed) | agent `quote.attachment_analyze`, started_at/completed_at/latency_ms/llm_model/cost_usd/error_message 그대로 |
| `rfq_auto_analyses` (completed/failed) | agent `rfq_auto.analyze`, kind job, 동일 |
`[source_type, source_id]` UNIQUE + `insert_all(on_duplicate: :skip)` → 여러 번 돌려도 안전. 운영 1회: `kamal app exec --reuse "bin/rails agent_runs:backfill"`.

---

## ④ 이슈 분해표 (7개 · 부모가 registry 등록)

| ID | 제목 | type | P | 하는 일 | 완료 판정 기준 (검증 가능) | 선행 | h |
|---|---|---|---|---|---|---|---|
| **422-A** | [Agent관제] agent_runs 테이블 + AgentRun.track 기록 헬퍼 + 기존 3테이블 백필 | GENERATE_CODE | P0 | §③ 스키마 마이그레이션, `AgentRun` 모델(track/start!/finish!/fail!/NullRun, 스코프 in_window/for_agent), `lib/tasks/agent_runs.rake` 백필. 기존 코드 무수정 | ① `bin/rails db:migrate` 후 `schema.rb`에 agent_runs + 인덱스 6개. ② 모델 테스트: 블록 예외 시 status=failure·error_message 기록 후 **예외가 재발생**함 / DB 쓰기 실패를 stub하면 raise 없이 `Rails.logger.warn` 1회 호출되고 블록 반환값 그대로. ③ 테스트 DB에 3테이블 fixture 각 2행 넣고 rake 2회 실행 → agent_runs 정확히 6행(멱등). ④ 기존 전체 테스트 0 failure(회귀 없음) | — | 4 |
| **422-B** | [Agent관제] Stage 2 Haiku 비용 미기록 수정 — CostGuard 과소집계 | FIX_BUG | P1 | `Gmail::LlmRfqAnalyzerService#parse_response`가 `response.usage`(input/output/cache_read)를 파싱해 `cost_usd/input_tokens/output_tokens`를 반환하도록. 단가 상수는 `SonnetEscalatorService#compute_cost` 패턴 재사용, Haiku 4.5 단가는 `claude-api` 스킬로 확인 후 기입. `normalize_haiku`는 무수정 | ① usage를 stub한 응답으로 `analyze` → `cost_usd > 0`, 토큰 수 일치(단위 테스트). ② `ClassificationOrchestrator` 테스트에 stage_reached=2 행의 `cost_usd > 0` 단언 추가·통과. ③ fallback 경로(`llm_unavailable`)는 `cost_usd` 0 유지. ④ `test/services/gmail/cost_guard_test.rb` 통과 | — | 1.5 |
| **422-C** | [Agent관제] 1차 계측 — 분류·Rfp 첨부분석·견적첨부·RFQ Auto 4경로 미러/래핑 | GENERATE_CODE | P0 | §③ 표의 4경로. 각 write는 rescue+warn 안. `EmailToOrderService` 백링크 1줄. `Rfp::AnalyzeAttachmentsJob`은 부모+자식 2행으로 비용을 **처음으로 저장** | ① 각 경로 테스트에서 실행 1회당 agent_runs 행 수·agent_name·status·cost_usd 단언(Rfp 잡: 부모1+자식2, item_extract 행의 cost = `_cost_usd`). ② 각 경로에서 `AgentRun` 쓰기를 강제 실패시켜도 **본 기능 결과(주문 생성·aqa completed·태스크 생성)가 동일**하고 warn 로그만 남음. ③ 기존 orchestrator/aqa/rfq_auto/rfp 테스트 전부 통과(회귀 0). ④ 개발 서버에서 칸반 첨부 분석 1회 실행 → `/admin/agent_runs` S4에 부모·자식 막대 표시 스크린샷 | 422-A | 4 |
| **422-D** | [Agent관제] 단일 페이지 `/admin/agent_runs` — 헤더·KPI·에이전트별 집계·최근 실행 피드·빈 상태·사이드바 | GENERATE_CODE | P1 | §② S1·S2·S3·S5 + 빈 상태 3층 + 라우트/컨트롤러(`require_admin!`)/사이드바 링크/`ko`·`en` 키. brand-dna 토큰 준수. `[Gmail 동기화 실행]` CTA는 `inbox_sync_path` 재사용 | ① `test/controllers/admin/agent_runs_controller_test.rb`: admin 200 / manager·member 리다이렉트 / 0행일 때 빈 상태 카드 문구 포함 / window=24h·agent·status 필터 반영. ② 캐릭터 저니(admin): 로그인 → 사이드바 "Agent 관제" → 빈 상태 카드 → 백필 데이터 넣은 뒤 KPI·집계·피드 표시 → CTA 클릭 시 토스트 — Playwright 스크린샷 4장. ③ brand-guardian 자가검증 4항목(hero CTA·anti_patterns·CTA 존재·0.5초 룰) 통과. ④ 페이지 로드 SQL ≤ 10쿼리(log 확인) | 422-A | 6 |
| **422-E** | [Agent관제] 주문별 타임라인(막대·중첩·실패) + 실행 상세 패널 (Turbo Frame) | GENERATE_CODE | P1 | §② S4·S6. `order_timeline`/`show` 액션 + 프레임 파셜. 막대 폭 비례·상태 색·parent 들여쓰기·meta JSON 뷰·원본 레코드 링크 | ① 컨트롤러 테스트: `orders/:order_id` 프레임이 해당 주문 run만 반환·부모→자식 순서·max_duration 기준 폭 계산값 검증, `show`가 meta JSON과 error_message 렌더. ② 저니: 주문 카드 펼침 → 막대 표시 → 실패 행 빨강 → 클릭 → 우측 패널에 판정근거·오류 원문 — 스크린샷 3장. ③ 20개 주문 카드 초기 렌더 시 타임라인 SQL 0회(lazy 확인) | 422-D, 422-C | 4 |
| **422-F** | [Agent관제] 데이터 유입 재개 결정 — 자동 Gmail sync 재활성화 범위 [CONFIRM] | FEATURE_PLAN | P1 | **코드가 아니라 결정.** 2026-05-30 정지된 `gmail_sync_all` 재개 여부·주기. 권고: **"된다" — CostGuard 일 $0.35 상한이 살아 있어 월 최대 ≈$10.5**, 정지 사유에 SQLite BusyException(2026-05-07)도 있으므로 매시간이 아닌 **하루 2회(09:05·15:05)** 로 시작. T2 BUDGET → `request-user-confirm.sh` 필수(`payload.requires_user_confirm: true`) | ① 대표님 답변이 registry에 기록됨. ② 승인 시 `config/recurring.yml` 4줄 수정·배포 후 24h 내 `agent_runs`에 `gmail.classify` 행 ≥ 1 + `/admin/agent_runs` S2 CostGuard 게이지에 금일 비용 > 0. ③ 거부 시 빈 상태 카드 문구를 "수동 동기화 운영 중"으로 갱신 | 422-A(승인 후 실행은 422-C 이후) | 0.5 |
| **422-G** | [Agent관제] 2차 계측 확대 — 답변초안·Rfp 분류/긴급초안·분류 stage 자식·RFQ Auto step 자식·insight 잡 | GENERATE_CODE | P2 | usage 파싱 없는 4서비스(`RfqReplyDraftService`, `Rfp::AttachmentClassifier`, `Rfp::UrgentQuoteEmailDrafter`, vision 자식)에 산출+기록, `gmail.classify` stage 1/2/3 자식 행, `rfq_auto` step 자식, `AgentInsightJob`(kind job, 비용 0). **422-D 화면을 본 뒤 대표님 판단으로 착수** | ① 각 서비스 테스트에서 agent_runs 행·cost_usd > 0. ② S3 집계에 신규 agent_name 6개 표시. ③ 회귀 0 | 422-E | 3 |

### 실행 순서
```
422-A(4h) ─┬─ 422-D(6h) ── 422-E(4h) ── 422-G(3h, 판단 후)
           ├─ 422-C(4h) ──┘
           └─ 422-F(0.5h, 결정 — A 착수와 동시에 대표님께 T2 질의)
422-B(1.5h) — 독립. C와 같은 파일군이므로 C 직후 처리
```
대표님이 화면을 보시는 시점: **A + D = 10h**. 그 시점 데이터 = 운영DB 백필분(있으면) + 수동 동기화/칸반 첨부분석으로 만든 실행.

## ⑤ 총 공수 · 부모 확인 항목 · 더 하면 좋은 것

**총 estimated_hours = 23h** (A4 + B1.5 + C4 + D6 + E4 + F0.5 + G3). 1차 가치 구간(A·C·D·E) = 18h.

**부모(Opus) 확인 항목 — 기획이 의존하는 미실측 2건**
1. 운영DB 행수(read-only): `kamal app exec --reuse "bin/rails runner 'puts [ClassificationLog.count, ClassificationLog.maximum(:created_at), AttachmentQuoteAnalysis.count, RfqAutoAnalysis.count].inspect'"` → 백필로 첫날 보일 이력의 양이 정해진다. 0이어도 기획은 바뀌지 않는다(빈 상태 설계 유효).
2. 디자인 토큰 충돌: 부모 지시(#1E3A5F/#00A1E0) vs `brand-dna.json`(#166c72, navy는 anti_pattern). 본 기획은 brand-dna를 따른다 — 뒤집으려면 brand-dna를 바꾸는 것이 순서(T2 DIRECTION).

**범위 밖 발견(별도 이슈 후보, 본 작업에서 손대지 않음)**
- `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`가 운영 런타임에 `.claude/issue-db/registry.json`을 직접 쓴다 → agent_runs 도입 후 제거 대상(REFACTOR).

**더 하면 좋은 것(부수적 이익, 1차 범위 아님)**
- `AgentRun after_create_commit → Turbo Stream prepend "agent_runs"` → S5 피드 실시간(약 1h). 대표님이 동기화 버튼을 누르고 화면에서 막대가 자라는 것을 본다.
- 관제 데이터가 쌓이면 CostGuard 게이트를 "분류 전용 $0.35"에서 "에이전트별 예산"으로 확장 가능(`agent_runs` 집계 기반). 단 B안 회귀 사유 때문에 **새 게이트로 추가**하지 기존 게이트를 대체하지 않는다.
- 고객 설명용: 주문 드로어에 "AI 판정 근거" 링크(S6 `show` 프레임 재사용) — 제안서 §2-② 설명 가능성.
