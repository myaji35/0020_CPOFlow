# ISS-422 [Agent관제] 에이전트 실행 모니터링 단일 페이지 — 기획 (v2, 운영DB 실측 반영)

> 2026-09-03 · plan-harness:product (Fable 5.1) · 입력: `docs/proposals/agent-observability-제안_260903.md`
> 검증: 코드(`app/`)·스키마(`db/schema.rb`)·`config/recurring.yml`·git log 직접 대조 + **운영DB 실측(Opus, 158.247.235.31 `cpoflow_storage/production.sqlite3`, 133MB, 최종수정 2026-05-30)**.
> v1(개발DB 기준 "테이블이 비어 있다") 전제는 폐기. 개발DB(orders 6건)는 운영과 무관했다.

## 판정: 된다 — 지금 있는 14,247행으로 페이지를 먼저 띄운다
`agent_runs` 1개 테이블 신설(C안) + 운영 `classification_logs` 14,247행 백필 → `/admin/agent_runs` 단일 페이지. 기존 테이블·CostGuard 무수정.
동시에 발견된 **분류 파이프라인 결함 2건(비용 전부 $0 → 예산 가드 무력화, Sonnet 에스컬레이션 0/237 성공)** 을 P0 FIX_BUG로 분리한다.
전제: 운영 컨테이너가 떠 있어야 운영에서 확인 가능(인프라는 부모 별도 이슈).

---

## ① 실측 대조표 — 제안서 주장 / v1 전제 vs 운영 실제

### 운영DB 실측 (2026-09-03, Opus)
| 테이블 | 행수 | 비고 |
|---|---|---|
| orders | 11,971 | |
| classification_logs | **14,247** | cost_usd 합계 **$0.0** · 최종 2026-05-06 · 모델별 rule-only 13,904(97.6%) / **haiku-4.5-fallback 237** / haiku-4.5 106 / **sonnet-4.5 0** |
| attachment_quote_analyses | 3 | |
| rfq_auto_analyses | 17 | |

| # | 주장 (제안서 / v1) | 실측 | 판정 / 기획 반영 |
|---|---|---|---|
| 1 | "데이터가 없어 화면을 먼저 못 만든다"(v1 전제) | classification_logs 14,247행이 order_id로 orders 11,971건과 연결됨 | **틀림. 화면이 1순위.** 백필(멱등 rake) → 페이지. 계측 확대는 화면을 본 뒤 |
| 2 | 비용 집계가 2곳뿐 | 산출 코드는 12파일, 저장은 3테이블. 그러나 **운영 classification_logs cost 합계 $0** — Haiku 실호출 343건(106+237)이 전부 0. 원인은 코드로 확정: `Gmail::LlmRfqAnalyzerService#parse_response`가 `response.usage`를 파싱하지 않아 cost 키가 없음 → `ClassificationOrchestrator#normalize_haiku`의 `haiku_hash[:cost_usd].to_f` = 0.0 → `log_and_return`이 0을 기록. fallback 행도 `haiku_value(:cost_usd)` = 0. Sonnet만 `compute_cost`가 있는데 성공 행이 0건이라 합계가 정확히 $0 | **P0 결함.** `Gmail::CostGuard.today_cost = ClassificationLog.v2.sum(:cost_usd)`가 항상 0 → **일 $0.35 예산 가드가 운영 기간 내내 무력화**돼 있었다. 이슈 422-B |
| 3 | (신규 발견) Stage 3 Sonnet | 모델 라벨 `sonnet-4.5`(성공 시 `sonnet_escalator_service.rb:204`) 행이 **0건**, `haiku-4.5-fallback`(Sonnet 실패 → Haiku 결과 채택, L226) 237건 | **Sonnet 에스컬레이션이 운영에서 한 번도 성공하지 못했다(0/237).** reason 컬럼에 원인이 남아 있다: `stage3_fallback_to_stage2: api_returned_nil \| parse_failed \| exception:<Class>`. 부모 확인 쿼리 §⑤-1. 422-B에 포함 |
| 4 | agent_runs 신설 필요 | classification_logs 존재. 단 **input/output_tokens 컬럼 없음**(cost_usd 10,6 · latency_ms만), 분류 도메인 전용(verdict/is_rfq/would_exclude), `ClassificationLog.v2` 스코프 소비자 5곳(CostGuard·ClassifyV2Day3Gate·ShadowFnDetectorJob·Admin::RfqStats·EmailToOrderService 백링크) | **C안**(§③). classification_logs에는 컬럼을 추가하지 않는다. 토큰 컬럼은 agent_runs가 가진다 |
| 5 | LLM 호출 18곳 / 잡 23개 | 참조 파일 16개, 실 API 호출 서비스 10개, 잡 27개 | 수치 정정. 계측 단위는 "실행 경로" |
| 6 | 비용 큰 곳부터 계측 | 운영 실측상 처리량의 97.6%는 **rule-only(LLM 미경유)**. LLM 경로는 343건(2.4%) | "LLM 비용"만 보여주면 화면이 빈다. **처리량(규칙/Haiku/Sonnet/RFQ번호 직행)** 을 1급 지표로 올린다(§②-S2·S3) |
| 7 | 사각지대 | `EmailSyncJob` L98: `has_rfq_number`면 Orchestrator를 아예 건너뛰어 **로그가 남지 않는다**. 이 주문은 `orders.classifier_version='v1'`, `rfq_no` present로만 식별 가능 | 신규 유입은 422-C에서 `gmail.rfq_number_gate` 행(rule-only, cost 0) 1줄 추가로 봉합. 과거분은 orders에서 카운트해 S2 타일에 "RFQ번호 직행 N건"으로 표시 |
| 8 | 최종 기록 2026-05-06 (약 4개월 정지) | git: 05-08 `fix(prod): 500 에러 안정화 — Kamal 자동 게이트`, 05-10 recurring.yml 변경, recurring 주석 "2026-05-07 BusyException → 15분→1시간", **05-30 `02caf09` 자동 Gmail sync 명시 비활성화**. DB 최종수정도 05-30 → 05-30 이후엔 앱 자체가 안 쓰였다. 05-06~05-30 사이 24일간 로그 0건의 코드상 후보: (a) `EmailAccount#ready?` false(토큰 만료·refresh 불가) → `sync_account`가 warn만 남기고 return(L37~40) — **가장 유력**(사용자 화면엔 아무 표시 없음) (b) 05-07 BusyException 대응 중 recurring 잡 미등록 (c) 모든 메일이 idempotency/`has_rfq_number`로 skip(가능성 낮음 — 그래도 gate 행은 없으니 식별 불가) | 코드만으로는 (a)/(b) 확정 불가 → 운영 로그·`EmailAccount` 상태 조회가 필요. **별도 이슈로 쪼개지 않고 422-F(유입 정지 진단 + 재개 결정)에 통합** — 재개 결정의 선행 조건이라 같은 사람이 같은 시점에 본다 |
| 9 | 부수 발견 | `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`가 운영 런타임에 `.claude/issue-db/registry.json`을 직접 쓴다 | 범위 밖. REFACTOR 후보로 보고만 |

**비용 산출 현황(계측 설계 근거)**: Sonnet Stage 3 `compute_cost`(cache_read 포함) ✔ 있으나 성공 0건 / Vision(QuoteItemExtractor·RfqAuto::VisionItemExtractor) 상수 산출 ✔ 저장 ✔ / `Rfp::ItemExtractor`·`Rfp::SummaryReportService` 산출 ✔ **저장 ✘**(잡이 버림·logger.info만) / **Haiku Stage 2 산출 ✘(0 고정)** / `RfqReplyDraftService`·`Rfp::AttachmentClassifier`·`Rfp::UrgentQuoteEmailDrafter` 산출 ✘.

---

## ② 단일 페이지 화면 설계 — `/admin/agent_runs`

### 기본 사양
| 항목 | 결정 |
|---|---|
| 라우트 | `namespace :admin { resources :agent_runs, only: %i[index show] do collection { get "orders/:order_id", action: :order_timeline, as: :order_timeline } end }` → `GET /admin/agent_runs`(페이지) · `GET /admin/agent_runs/:id`(상세 Turbo Frame) · `GET /admin/agent_runs/orders/:order_id`(타임라인 Turbo Frame). **URL 1개**, 나머지는 같은 페이지 안의 프레임 요청 |
| 컨트롤러 | `Admin::AgentRunsController` — `before_action :require_admin!` |
| 권한 | **admin 전용**(비용·프롬프트 요약·오류 원문). 사이드바 `_sidebar.html.erb` L135 admin 페르소나 블록(메뉴 권한·피드백 관리 옆), 아이콘 `lni lni-pulse`, 라벨 `t("nav.agent_runs", default: "Agent 관제")` |
| 필터 | `window` = `7d`/`30d`/`90d`/`all`(**기본 `all`** — 운영 이력이 05-06에 멈춰 있어 7일 기본이면 첫 화면이 빈다. 유입 재개 후 `7d`로 바꾼다) · `agent` · `model`(rule-only/haiku-4.5/haiku-4.5-fallback/sonnet-4.5/…) · `status` · `q`(주문 id·제목) |
| 언어 | 개발 한국어, `t(..., default: "한국어")` 패턴 + `en.yml` 키 |
| 디자인 토큰 | **`brand-dna.json`(_status active) 우선**: hero `#166c72` = 주요 CTA·활성 필터, `shell_bg #1E3A5F`는 사이드바만, 배지 solid+흰 글자, radius ≤ 7px, 13px dense, Line/Feather outline. ⚠ 지시값 `#1E3A5F`/`#00A1E0`는 brand-dna anti_patterns("SLDS navy → Deep Teal")와 충돌 → brand-dna를 따른다(뒤집으려면 brand-dna 변경이 순서, T2 DIRECTION) |
| 주요 CTA(MUST_EXIST) | `[Gmail 동기화 실행]` → 기존 `POST /inbox/sync`(`inbox_sync_path`) 재사용 → 토스트. 유입 장치가 곧 첫 행동 |
| 새로고침 | 수동 버튼 + "마지막 집계 HH:MM". 실시간 스트림은 범위 밖(§⑤) |

### 섹션 구성 (한 화면 세로 스크롤)

**S1 헤더바** — "Agent 관제" · 부제 "어떤 에이전트가 어느 주문에 관여해 얼마를 썼는지" · 기간 세그먼트 · 에이전트/모델/상태 select · 주문 검색 · `[Gmail 동기화 실행]`(hero) · `[새로고침]`. 헤더 아래 1줄 상태 스트립: **"자동 동기화: 정지(2026-05-30) · 마지막 분류 기록: 2026-05-06"** — `config/recurring.yml`의 상태는 코드로 알 수 없으므로 `AgentRun.maximum(:started_at)`과 `SolidQueue::RecurringTask.exists?(key: "gmail_sync_all")`로 산출.

**S2 KPI 스트립(6타일)**
| 타일 | 값 | 출처 |
|---|---|---|
| 실행 수 | `AgentRun.in_window.count` | agent_runs |
| **처리 경로** | 규칙 N / Haiku N / Sonnet N / **RFQ번호 직행 N** — 각 %와 미니 스택바 | agent_runs `group(:model)` + `Order.where.not(rfq_no: nil).where(classifier_version: "v1")`(과거 직행분; 422-C 이후엔 `gmail.rfq_number_gate` 행) |
| 총 비용 | `sum(:cost_usd)` — **cost_usd NULL 행이 있으면 "미집계 N건" 각주** | agent_runs |
| 실패율 | failure / (success+failure) — fallback(`haiku-4.5-fallback`, `stage3_*_failure`)은 별도 "폴백 N건" 배지 | agent_runs.status + meta |
| 평균 소요 | `average(:duration_ms)` | agent_runs |
| 오늘 분류 예산 | `Gmail::CostGuard.status` 게이지 + OK/WARN/BLOCKED. **422-B 전에는 "비용 미산출 — 가드 무력" 경고 배지**(합계 0인데 LLM 행이 있으면 표시) | classification_logs(기존 로직 무수정) |

**S3 에이전트별 집계(표)** — 행 = `agent_name × model`(gmail.classify는 rule-only/haiku/sonnet/fallback로 갈라져야 97.6%의 의미가 보인다). 컬럼: 에이전트 · 모델 · 실행수 · **처리량 비중 막대** · 총비용 · **비용 비중 막대** · 평균 소요 · 실패/폴백율 · 마지막 실행. 정렬 토글(처리량/비용). 최상위 행 "비용의 N%" 배지.

**S4 주문별 타임라인(LangSmith 대응 핵심)** — 기간 내 관여 주문 최근 20건(검색 시 해당 주문). 카드 헤더: `#id · Order#display_subject · 에이전트 N · 총 소요 · 총 비용 · [실패 n] [폴백 n]`. 펼침 → `<turbo-frame id="order-timeline-{id}" src=… loading="lazy">`:
```
#1042  RFQ 접수 → 첨부분석                          총 8.4s · $0.312 · 폴백 1
 gmail.classify (haiku-4.5-fallback)  ▌         0.9s   $0.000  fallback  "stage3_fallback_to_stage2: exception:Faraday::…"
 rfp.analyze_attachments              ██████████████ 6.9s $0.271 success
   └ rfp.item_extract                 ██████████  4.8s   $0.190  success  claude-sonnet-4-6
   └ rfp.summary_report               ████        2.0s   $0.081  success
 gmail.reply_draft                    ██          1.2s   —(미집계) failure  "AnthropicCreditError: …"
```
막대 폭 = `duration_ms / 주문 내 max * 100%`(최소 2%). 색: success `ok #2e9856` · fallback `warn #d99a2a` · failure `danger #c84431` · skipped `text_secondary` · rule-only는 얇은 회색 선(0ms여도 존재를 보인다). `parent_run_id` 들여쓰기. 행 클릭 → S6. 차트 라이브러리 없음(Tailwind div + inline width).

**S5 최근 실행 피드(표)** — pagy 50건. 시각 · 에이전트 · 모델 · 주문(칸반 드로어 링크) · 소요 · 비용(NULL → "—") · 상태 배지 · reason/오류 60자. 행 클릭 → S6.

**S6 실행 상세 패널** — 우측 고정 `<turbo-frame id="agent-run-detail">`. 기본(agent/kind/status/model) · 타이밍 · 토큰/비용(NULL → "이 실행은 토큰을 기록하지 않았습니다(422-B 이전)") · **meta JSON**(verdict/stage_reached/reason/confidence/would_exclude — "왜 excluded인가" 설명용) · error_message 전문 · 원본 레코드 링크(`source_type/source_id`) · 주문 드로어 링크.

### 빈 상태 — 세 층
| 상황 | 표시 |
|---|---|
| agent_runs 전체 0행(백필 전·신규 설치) | 안내 카드 1장: "기록된 실행이 없습니다. `bin/rails agent_runs:backfill`로 기존 분류 이력을 가져오거나 [Gmail 동기화 실행]" + 행동 3버튼(동기화/칸반 첨부분석/LAB RFQ Auto). S2 CostGuard·S1 상태 스트립은 유지 |
| 기간 내 0행(전체는 있음) — **운영 기본 상황**(마지막 05-06) | 섹션 자리에 "최근 {window} 실행 없음 — 마지막 기록 2026-05-06 · 자동 동기화 정지 상태 [전체 기간 보기]". 기본 window가 `all`이므로 첫 화면에서는 안 나온다 |
| 섹션 부분 비어 있음 | S4: "주문 미연결 실행 N건은 아래 피드에" |

### 성능·안전
- 14,247행 규모: 집계는 인덱스(`created_at`, `[agent_name, model, created_at]`, `[order_id, started_at]`, `status`)로 처리. `all` 기본이라 집계 쿼리 6~8개가 전 범위 GROUP BY — SQLite 1만 행대는 수십 ms. 10만 행 넘으면 기본 window를 30d로.
- S4 lazy 프레임, `includes(:order)`. 페이지는 읽기 전용(쓰기는 기존 sync 엔드포인트뿐).

---

## ③ 데이터 모델 판정 — **C안 (agent_runs 신설 + 기존 3테이블 미러·백필 병합)**

### A/B/C 비교
| 안 | 회귀 위험 | 결정적 결함 |
|---|---|---|
| A 신설만 | 낮음 | 운영 14,247행이 화면에 안 보임. 진실 소스 이원화 |
| B classification_logs 확장(+agent_name/kind/status/started_at/input_tokens/output_tokens/error_message/parent_id 8컬럼) | **높음** — `ClassificationLog.v2` 소비자 5곳 수정, `classifier_version NOT NULL`·`verdict`·`would_exclude` 등 분류 전용 제약이 타 에이전트에 무의미 | `CostGuard.today_cost = ClassificationLog.v2.sum(:cost_usd)`에 첨부분석 Sonnet vision(건당 $0.02~)이 섞이면 **일 $0.35 게이트가 오발동해 분류를 꺼버린다**. 422-B로 가드를 살리는 순간 이 위험이 현실이 된다 |
| **C** | **낮음** — 기존 테이블·쿼리·모델 무수정. write 3곳에 rescue 안 1~3줄 | 없음. 도메인 로그(왜)는 제자리, 관제 로그(누가·언제·얼마)는 agent_runs. `source_type/source_id`로 연결 |

**classification_logs 컬럼 추가 범위: 0개.** 토큰(input/output/cache_read)은 agent_runs가 가진다. 분류 경로의 토큰은 422-B가 `LlmRfqAnalyzerService`에 usage 반환을 넣은 뒤, `ClassificationOrchestrator`가 `haiku_hash[:input_tokens]` 등을 인스턴스 변수로 잡아 미러 행에 쓴다(`ClassificationResult` Data.define은 무수정 — 테스트 다수가 위치 인자로 생성).

### 스키마 (`create_table :agent_runs`)
```ruby
t.references :order, null: true
t.string   :agent_name,  null: false     # gmail.classify / gmail.rfq_number_gate / quote.attachment_analyze / rfp.analyze_attachments / rfp.item_extract / rfp.summary_report / rfq_auto.analyze …
t.string   :kind,        null: false, default: "service"   # job | service | stage
t.string   :status,      null: false, default: "running"   # running | success | fallback | failure | skipped
t.datetime :started_at,  null: false
t.datetime :finished_at
t.integer  :duration_ms
t.string   :model                          # rule-only / haiku-4.5 / haiku-4.5-fallback / sonnet-4.5 / claude-sonnet-4-6 …
t.integer  :input_tokens, :output_tokens, :cache_read_tokens
t.decimal  :cost_usd, precision: 10, scale: 6, null: true   # NULL = 미집계(0으로 위장 금지)
t.text     :error_message                  # 1,000자 절단
t.text     :meta                           # JSON ≤ 4KB — 판정근거·요약만, 입출력 원문 금지
t.string   :source_type; t.bigint :source_id
t.integer  :parent_run_id
t.timestamps
# index: created_at / [agent_name, model, created_at] / [order_id, started_at] / status / parent_run_id / [source_type, source_id] UNIQUE
```
`status: fallback`을 추가한 이유: 운영 데이터의 237건이 "성공도 실패도 아닌 폴백"이며 이것이 곧 Sonnet 장애 신호다. success로 뭉개면 화면이 문제를 숨긴다. 제안서의 input/output_digest는 제외(사용처 없음).

### 기록 헬퍼 `AgentRun.track` — 실패경로 4문항
```ruby
AgentRun.track(agent: "rfp.item_extract", order: order, kind: "service", parent: parent_run) do |run|
  result = Rfp::ItemExtractor.call(text)
  run.note(cost_usd: result["_cost_usd"], input_tokens: result["_input_tokens"], output_tokens: result["_output_tokens"],
           model: Rfp::ItemExtractor::MODEL, meta: { items: result["items"]&.size })
  result
end
run = AgentRun.start!(agent:, order:, source:) … run.finish!(…) / run.fallback!(reason) / run.fail!(error)   # 자체 rescue가 있는 잡용
```
| 문항 | 답 |
|---|---|
| 1 가짜 채우기 | 기록 실패 → `NullRun` no-op, 본 기능 계속. 비용 미산출 경로는 `cost_usd NULL` → 화면 "미집계". 0으로 쓰지 않는다 |
| 2 무음 실패 | 모든 쓰기 `rescue StandardError => e; Rails.logger.warn("[AgentRun] write failed agent=… #{e.class}: #{e.message}")`. raise 금지 |
| 3 사용자 인지 | 블록 예외는 `fail!` 후 **re-raise**(호출자 rescue·폴백 태스크 무변경). 화면 S2/S4/S5에 failure·fallback 표시 + S2 "가드 무력" 경고 |
| 4 금전 정합 | 관제는 돈을 움직이지 않는다. CostGuard는 기존 classification_logs 그대로 |

### 백필 `bin/rails agent_runs:backfill` (422-A) — 운영 14,267행 대상
| 원본 | 매핑 |
|---|---|
| classification_logs 14,247 | agent `gmail.classify`, kind service, model 그대로, started_at = created_at − latency_ms, **status**: reason LIKE 'safety_fallback%' → failure / model IN ('haiku-4.5-fallback','rule-only-fallback') → fallback / else success, cost_usd: **model='rule-only'면 0, LLM 모델인데 0이면 NULL(미집계 — 422-B 이전 행)**, meta {verdict, stage_reached, reason, confidence, would_exclude, is_rfq}, source=ClassificationLog |
| attachment_quote_analyses 3 | agent `quote.attachment_analyze`, started_at/completed_at/latency_ms/llm_model/cost_usd/error_message |
| rfq_auto_analyses 17 | agent `rfq_auto.analyze`, kind job, user_id는 meta |
`insert_all`(1,000행 배치) + `[source_type, source_id]` UNIQUE `on_duplicate: :skip` → 멱등. 운영 1회: `kamal app exec --reuse "bin/rails agent_runs:backfill"` (컨테이너 기동 후).

### 1차 계측 6경로 (422-C) — "가장 자주·비싸게"의 운영 근거
| 우선 | 경로 | 근거 | 방식 |
|---|---|---|---|
| 1 | `ClassificationOrchestrator#log_and_return` | 운영 최다(14,247). 유입 재개 시 그대로 최다 | **미러** 1행(source=log, 토큰은 orchestrator 인스턴스 변수에서) + `EmailToOrderService` order_id 백링크 `update_all` 1줄 추가 |
| 2 | `EmailSyncJob` L98 `has_rfq_number` 분기 | 사각지대 봉합 | `gmail.rfq_number_gate` 행 1줄(kind stage, model rule-only, cost 0, meta {rfq_no}) |
| 3 | `Rfp::AnalyzeAttachmentsJob` | 건당 최고가, 비용 전량 유실 중 | 부모 `rfp.analyze_attachments` + 자식 `rfp.item_extract`(`_cost_usd/_input_tokens/_output_tokens`) + 자식 `rfp.summary_report`(`report[:cost_usd]`) |
| 4 | `QuoteAttachmentAnalyzeJob` | Sonnet vision | 미러(source=aqa) |
| 5 | `RfqAuto::Analyzer#call` | LAB 6단계 합산 | 미러(source=analysis) |
(usage 파싱이 없는 `RfqReplyDraftService`·`Rfp::AttachmentClassifier`·`Rfp::UrgentQuoteEmailDrafter`, 분류 stage 자식, rfq_auto step 자식은 **2차 422-G**)

---

## ④ 이슈 분해표 (7개 · 부모가 registry 등록)

| ID | 제목 | type | P | 하는 일 | 완료 판정 기준 | 선행 | h |
|---|---|---|---|---|---|---|---|
| **422-A** | [Agent관제] agent_runs 테이블 + AgentRun.track 헬퍼 + 운영 classification_logs 14,247행 백필 | GENERATE_CODE | P0 | §③ 마이그레이션, `AgentRun` 모델(track/start!/finish!/fallback!/fail!/NullRun, 스코프), `lib/tasks/agent_runs.rake`. 기존 코드 무수정 | ① `schema.rb`에 agent_runs+인덱스 6개. ② 모델 테스트: 블록 예외 → failure 기록 후 재발생 / 쓰기 실패 stub → raise 없이 warn 1회, 블록 반환값 유지. ③ fixture(classification_logs: rule-only·haiku-4.5 cost 0·haiku-4.5-fallback·safety_fallback 각 1 + aqa 1 + rfq_auto 1) rake 2회 → 6행(멱등), 상태 매핑 success/fallback/failure, LLM cost 0 → NULL. ④ 전체 테스트 0 failure. ⑤ **운영에서 1회 실행 → `AgentRun.count == 14,267`, `where(status:"fallback").count == 237`** | — | 4 |
| **422-B** | [Agent관제] 분류 파이프라인 결함 2건 — Haiku 비용 $0 고정(예산 가드 무력) + Sonnet 에스컬레이션 0/237 성공 | FIX_BUG | **P0** | (1) `LlmRfqAnalyzerService#parse_response`가 `response.usage`(input/output/cache_read)를 파싱해 `cost_usd`·토큰 반환(단가는 `SonnetEscalatorService#compute_cost` 패턴 + `claude-api` 스킬로 확인). `normalize_haiku` 무수정. (2) 운영 `reason` 분포(§⑤-1)로 Sonnet 실패 원인 특정 → 수정. 후보: `api_returned_nil`(ClaudeTokenResolver `create_client` nil·OAuth bearer가 Sonnet 미허용) / `exception:<Class>` / `parse_failed`. **P0 근거**: CostGuard가 무력해 재개 시 비용 상한 없음 + 에스컬레이션 전건 실패 = 모호 메일 판정 품질 저하 | ① usage stub → `cost_usd > 0`·토큰 일치; fallback 경로 cost 0 유지; orchestrator 테스트 stage 2 행 `cost_usd > 0`; `cost_guard_test` 통과. ② Sonnet: 원인 재현 테스트 작성 → 통과, `SonnetEscalatorService` 성공 경로가 `model: "sonnet-4.5"` 행 생성. ③ 운영 재개 후 첫 에스컬레이션 10건 중 `sonnet-4.5` ≥ 1(0/10이면 재진단). ④ S2 CostGuard 게이지 금일 비용 > 0 | 422-A(운영 원인 조회는 A와 무관, 즉시 가능) | 3 |
| **422-C** | [Agent관제] 1차 계측 — 분류 미러·RFQ번호 게이트·Rfp 첨부분석·견적첨부·RFQ Auto | GENERATE_CODE | P1 | §③ 표 5경로. 모든 write rescue+warn. Rfp 잡은 부모+자식 2행으로 비용을 처음 저장 | ① 경로별 테스트: 실행 1회당 행수·agent_name·status·cost(Rfp: 부모1+자식2, item_extract cost=`_cost_usd`; rfq_number 메일 → gate 행 1, classify 행 0). ② AgentRun 쓰기 강제 실패 시 본 기능 결과 동일 + warn만. ③ 기존 테스트 회귀 0. ④ 개발서버 칸반 첨부분석 1회 → S4 부모·자식 막대 스크린샷 | 422-A | 4 |
| **422-D** | [Agent관제] 단일 페이지 /admin/agent_runs — 헤더·상태 스트립·KPI(처리 경로 포함)·에이전트×모델 집계·최근 실행 피드·빈 상태·사이드바 | GENERATE_CODE | **P0** | §② S1·S2·S3·S5 + 빈 상태 + 라우트/컨트롤러(require_admin!)/사이드바/ko·en. 기본 window `all`. brand-dna 토큰. **백필 데이터만으로 완성되는 이슈 — 대표님 첫 화면** | ① 컨트롤러 테스트: admin 200 / manager·member 리다이렉트 / 0행 빈 상태 문구 / window·agent·model·status 필터 / rule-only 13,904·fallback 237 같은 집계값이 fixture 기준으로 정확. ② admin 저니(Playwright 스크린샷 4장): 사이드바 → 페이지(백필 데이터: 처리 경로 타일·에이전트×모델 표·피드) → 필터 → CTA 토스트. ③ brand-guardian 4항목. ④ 페이지 로드 SQL ≤ 12 | 422-A | 6 |
| **422-E** | [Agent관제] 주문별 타임라인(막대·중첩·폴백/실패) + 실행 상세 패널 (Turbo Frame) | GENERATE_CODE | P1 | §② S4·S6. 백필 데이터로 검증 가능(주문 11,971건 연결). rule-only 행도 표시 | ① `orders/:order_id` 프레임이 해당 주문 run만·부모→자식 순·폭 계산·fallback 색; `show`가 meta(reason·verdict·stage)·error 렌더. ② 저니 스크린샷 3장(펼침 → fallback 행 주황 + reason → 클릭 → 패널). ③ 카드 20개 초기 렌더 시 타임라인 SQL 0회 | 422-D | 4 |
| **422-F** | [Agent관제] 유입 정지 진단(2026-05-06) + 자동 Gmail sync 재개 결정 [CONFIRM] | FEATURE_PLAN | P1 | (1) 진단: 운영 `EmailAccount`(connected/토큰/refresh_token/last_synced_at) + 컨테이너 로그 `[EmailSyncJob]` warn 유무로 §①-8 (a)/(b) 확정. (2) 결정: 재개 여부·주기. 권고 **"된다"** — 단 **422-B 완료가 선행 조건**(가드가 무력한 채 재개하면 상한 없음). 시작은 하루 2회(09:05·15:05, BusyException 사유). T2 BUDGET → `request-user-confirm.sh`, `payload.requires_user_confirm: true` | ① 정지 원인이 (a)/(b)/(c) 중 하나로 registry에 기록. ② 승인 시 `recurring.yml` 4줄·재인증(필요 시) 후 24h 내 `gmail.classify` 행 ≥ 1, S1 상태 스트립 "자동 동기화: 실행 중". ③ 거부 시 S1 문구 "수동 동기화 운영 중" | 422-B(재개 실행), 진단은 즉시 | 1 |
| **422-G** | [Agent관제] 2차 계측 확대 — 답변초안·Rfp 분류/긴급초안·분류 stage 자식·RFQ Auto step 자식·insight 잡 | GENERATE_CODE | P2 | usage 파싱 없는 4서비스 산출+기록, `gmail.classify` stage 1/2/3 자식, rfq_auto step 자식, `AgentInsightJob`(kind job, 비용 0). **422-D 화면을 본 뒤 대표님 판단으로 착수** | ① 서비스별 행·cost>0. ② S3에 신규 agent 6개. ③ 회귀 0 | 422-E | 3 |

### 실행 순서
```
422-A(4h) ─┬─ 422-D(6h) ── 422-E(4h) ── 422-G(3h, 판단 후)
           ├─ 422-B(3h)  ── 422-F 재개 실행(승인 시)
           └─ 422-C(4h)
422-F 진단(즉시, 운영 조회) ─ 결정은 B 이후
```
**대표님 첫 화면 = A + D = 10h**, 운영 14,247행이 처리 경로·에이전트×모델·피드로 보인다. E까지 14h면 주문별 타임라인. 계측(C)·유입 재개(F)는 그 다음.

## ⑤ 총 공수 · 부모 확인 항목 · 더 하면 좋은 것

**총 estimated_hours = 25h** (A4 + B3 + C4 + D6 + E4 + F1 + G3). 첫 화면 구간 A·D = 10h, 1차 가치 구간 A·B·D·E = 17h.

**부모(Opus) 확인 항목 — read-only 운영 쿼리 (컨테이너 기동 후)**
1. Sonnet 실패 원인: `select reason, count(*) from classification_logs where model='haiku-4.5-fallback' group by 1 order by 2 desc;` → `api_returned_nil` / `parse_failed` / `exception:<Class>` 분포가 422-B (2)의 출발점.
2. 유입 정지 원인: `select id, email, connected, last_synced_at, gmail_token_expires_at, (refresh_token is not null) from email_accounts;` + `kamal app logs | grep "\[EmailSyncJob\]"` → 422-F 진단.
3. 디자인 토큰: brand-dna `#166c72` vs 지시 `#1E3A5F` — 본 기획은 brand-dna.

**범위 밖 발견(별도 이슈 후보)**: `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`의 런타임 registry.json 직접 쓰기 → agent_runs 도입 후 제거(REFACTOR). 운영 컨테이너 정지·도메인 타 프로젝트 서빙은 부모 인프라 이슈(본 기획은 "앱이 떠 있어야 운영 확인 가능" 의존성만 인지).

**더 하면 좋은 것**: `AgentRun after_create_commit → Turbo Stream prepend`로 S5 실시간(≈1h) / 주문 드로어에 "AI 판정 근거" 링크(S6 재사용, 고객 설명용) / 에이전트별 예산 게이트는 기존 CostGuard 대체가 아닌 신규 추가로.
