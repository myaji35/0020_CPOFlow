# ISS-422 [Agent관제] 에이전트 실행 모니터링 단일 페이지 — 기획 (v3, 운영 실측 + Sonnet 400 원인 축소)

> 2026-09-03 · plan-harness:product (Fable 5.1) · 입력: `docs/proposals/agent-observability-제안_260903.md`
> 검증: 코드(`app/`)·스키마(`db/schema.rb`)·`config/recurring.yml`·git log·anthropic gem 1.23.0 `dump_request` 실측 + `claude-api` 스킬 모델표 + **운영DB 실측(Opus, 158.247.235.31 `cpoflow_storage/production.sqlite3`, 133MB, 최종수정 2026-05-30)**.
> v1(개발DB 기준 "테이블이 비어 있다") 전제는 폐기. 개발DB(orders 6건)는 운영과 무관했다.
> **registry 매핑**: 422-A=ISS-423 · B=ISS-424 · C=ISS-425 · D=ISS-426 · E=ISS-427 · F=ISS-428 · G=ISS-429 (부모 등록 완료)

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

**classification_logs stage별 분포 (운영, 2026-09-03 Opus 조회)** — 화면 "처리 경로" 타일의 근거
| stage_reached | 건수 | 비율 | cost 합계 | 의미 (코드 기준) |
|---|---|---|---|---|
| 0 | 9,070 | 63.7% | $0.0 | `run_stage0` — Ariba 발신자 confirmed / 자사·제외 패턴 excluded (rule-only) |
| 1 | 4,834 | 33.9% | $0.0 | `Stage1::RuleGate` reject_no_signal → uncertain (rule-only) |
| 2 | 106 | 0.7% | $0.0 | Haiku confidence high 확정 (`haiku-4.5`) — **실호출인데 비용 0 = 버그** |
| 3 | 237 | 1.7% | $0.0 | Sonnet 에스컬레이션 — 성공 `sonnet-4.5` **0건**, 전부 `haiku-4.5-fallback`(confidence 0·verdict uncertain 237/237) |

**일자별 LLM 경로 분포 (운영)**: 04-09~04-26 fallback 229 · haiku 성공 0 / **04-27 haiku 20 + fallback 3(혼재)** / 04-28~04-30 haiku 82 · fallback 0(전부 high → stage 3 미호출, `classification_orchestrator.rb:67`) / 05-01 fallback 8 / 05-06 haiku 4. → Haiku 성공 106건은 모두 confidence 0.95·stage 2. **stage 3에 도달한 237건은 예외 없이 실패.**
| 합계 | 14,247 | | $0.0 | rule-only 13,904(97.6%) / LLM 경로 343(2.4%) |

**fallback 사유 (운영)**: `stage3_fallback_to_stage2: exception:Anthropic::Errors::BadRequestError` **237/237 전건 동일**. `api_returned_nil`·`parse_failed` 0건.

| # | 주장 (제안서 / v1) | 실측 | 판정 / 기획 반영 |
|---|---|---|---|
| 1 | "데이터가 없어 화면을 먼저 못 만든다"(v1 전제) | classification_logs 14,247행이 order_id로 orders 11,971건과 연결됨 | **틀림. 화면이 1순위.** 백필(멱등 rake) → 페이지. 계측 확대는 화면을 본 뒤 |
| 2 | 비용 집계가 2곳뿐 | 산출 코드는 12파일, 저장은 3테이블. 그러나 **운영 classification_logs cost 합계 $0** — Haiku 실호출 343건(106+237)이 전부 0. 원인은 코드로 확정: `Gmail::LlmRfqAnalyzerService#parse_response`가 `response.usage`를 파싱하지 않아 cost 키가 없음 → `ClassificationOrchestrator#normalize_haiku`의 `haiku_hash[:cost_usd].to_f` = 0.0 → `log_and_return`이 0을 기록. fallback 행도 `haiku_value(:cost_usd)` = 0. Sonnet만 `compute_cost`가 있는데 성공 행이 0건이라 합계가 정확히 $0 | **P0 결함.** `Gmail::CostGuard.today_cost = ClassificationLog.v2.sum(:cost_usd)`가 항상 0 → **일 $0.35 예산 가드가 운영 기간 내내 무력화**돼 있었다. 이슈 422-B |
| 3 | (신규 발견) Stage 3 Sonnet | 성공 라벨 `sonnet-4.5`(`sonnet_escalator_service.rb:204`) **0건**, `haiku-4.5-fallback`(L226) 237건, 사유 **`exception:Anthropic::Errors::BadRequestError` 237/237 동일**(운영 쿼리로 확정) | **Sonnet 에스컬레이션 0/237 — API가 매번 400을 반환한 고정 결함.** 코드 대조로 후보를 좁힌 결과는 아래 "Sonnet 400 원인 축소" 참조. 422-B(ISS-424)에 포함 |
| 4 | agent_runs 신설 필요 | classification_logs 존재. 단 **input/output_tokens 컬럼 없음**(cost_usd 10,6 · latency_ms만), 분류 도메인 전용(verdict/is_rfq/would_exclude), `ClassificationLog.v2` 스코프 소비자 5곳(CostGuard·ClassifyV2Day3Gate·ShadowFnDetectorJob·Admin::RfqStats·EmailToOrderService 백링크) | **C안**(§③). classification_logs에는 컬럼을 추가하지 않는다. 토큰 컬럼은 agent_runs가 가진다 |
| 5 | LLM 호출 18곳 / 잡 23개 | 참조 파일 16개, 실 API 호출 서비스 10개, 잡 27개 | 수치 정정. 계측 단위는 "실행 경로" |
| 6 | 비용 큰 곳부터 계측 | 운영 실측상 처리량의 97.6%는 **rule-only(LLM 미경유)**. LLM 경로는 343건(2.4%) | "LLM 비용"만 보여주면 화면이 빈다. **처리량(규칙/Haiku/Sonnet/RFQ번호 직행)** 을 1급 지표로 올린다(§②-S2·S3) |
| 7 | 사각지대 | `EmailSyncJob` L98: `has_rfq_number`면 Orchestrator를 아예 건너뛰어 **로그가 남지 않는다**. 이 주문은 `orders.classifier_version='v1'`, `rfq_no` present로만 식별 가능 | 신규 유입은 422-C에서 `gmail.rfq_number_gate` 행(rule-only, cost 0) 1줄 추가로 봉합. 과거분은 orders에서 카운트해 S2 타일에 "RFQ번호 직행 N건"으로 표시 |
| 8 | 최종 기록 2026-05-06 (약 4개월 정지) | git: 05-08 `fix(prod): 500 에러 안정화 — Kamal 자동 게이트`, 05-10 recurring.yml 변경, recurring 주석 "2026-05-07 BusyException → 15분→1시간", **05-30 `02caf09` 자동 Gmail sync 명시 비활성화**. DB 최종수정도 05-30 → 05-30 이후엔 앱 자체가 안 쓰였다. 05-06~05-30 사이 24일간 로그 0건의 코드상 후보: (a) `EmailAccount#ready?` false(토큰 만료·refresh 불가) → `sync_account`가 warn만 남기고 return(L37~40) — **가장 유력**(사용자 화면엔 아무 표시 없음) (b) 05-07 BusyException 대응 중 recurring 잡 미등록 (c) 모든 메일이 idempotency/`has_rfq_number`로 skip(가능성 낮음 — 그래도 gate 행은 없으니 식별 불가) | 코드만으로는 (a)/(b) 확정 불가 → 운영 로그·`EmailAccount` 상태 조회가 필요. **별도 이슈로 쪼개지 않고 422-F(유입 정지 진단 + 재개 결정)에 통합** — 재개 결정의 선행 조건이라 같은 사람이 같은 시점에 본다 |
| 9 | 부수 발견 | `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`가 운영 런타임에 `.claude/issue-db/registry.json`을 직접 쓴다 | 범위 밖. REFACTOR 후보로 보고만 |

### Sonnet 400 원인 축소 — 코드·SDK·모델표 대조 결과 (2026-09-03)
호출부 `sonnet_escalator_service.rb:56-64`: `client.messages.create(model: ENV.fetch("RFQ_SONNET_MODEL", "claude-sonnet-4-5-20250929"), max_tokens: 2048, system: [2개 text 블록 + cache_control ephemeral], messages: [user 1건])`. 클라이언트는 Haiku와 같은 `ClaudeTokenResolver.create_client`.

| 후보 | 검증 | 판정 |
|---|---|---|
| (a) 모델 ID 무효 | `claude-api` 스킬 `shared/models.md`: `claude-sonnet-4-5-20250929` = Sonnet 4.5 Full ID, **Active**. `RFQ_SONNET_MODEL` 환경변수는 deploy.yml·secrets에 없음(기본값 사용) | **제외** |
| (b) OAuth bearer/티어 미허용 | Haiku(106건 성공)와 **동일 클라이언트** 공유. `create_client`는 bearer면 API 키로 폴백, 없으면 nil → nil이면 `api_returned_nil`이어야 하는데 0건 | **제외** |
| (b′) Ruby SDK 파라미터명 (`system:` vs SDK 정식 `system_:`) | gem 1.23.0 `MessageCreateParams.dump_request`를 dev에서 실행 → 본문 키 `[:model, :max_tokens, :system, :messages]`, `system` 블록 그대로 통과(`base_model.rb` dump: 미정의 키는 `acc.store(name, val)`로 보존). **운영 gem 버전 = dev와 동일**: `Gemfile.lock` 이력 2026-02-22 이후 전 커밋 `anthropic (1.23.0)`, Dockerfile `BUNDLE_DEPLOYMENT=1`로 lock 고정 | **제외** |
| (c) max_tokens/파라미터 상한 | 2048 — Sonnet 4.5 상한 내. cache_control 브레이크포인트 2개(≤4). 최소 캐시 토큰 미만이면 **캐시가 안 될 뿐 400이 아니다**. 환경변수 `RFQ_SONNET_MODEL`/`RFQ_LLM_MODEL`은 deploy.yml·.kamal/secrets·.env(.dockerignore로 이미지 제외)에 없음 | **제외** |
| (d) 크레딧 소진 400 (Haiku·Sonnet 공통 실패) | **구간 ①(04-09~04-26)의 `haiku-4.5` 0건은 Haiku 실패를 뜻하지 않는다** — `classification_orchestrator.rb:67`은 confidence "high"일 때만 stage 2 행을 남기고, high가 아니면 로그 없이 곧장 Stage 3로 간다. 따라서 "Haiku가 매번 실패했다"와 "Haiku가 살아서 uncertain을 냈다"는 **stage 2 행 수만으로는 구별 불가**이며, 구간 ①과 ②는 단일 원인(Sonnet 고유 400)으로도 설명 가능하다 — 잔액설을 끌어올 필요는 이 근거만으로는 없다(부모 지적 반영). 다만 그 둘을 가르는 **다른 데이터가 있다**: **fallback 237행의 confidence가 전부 0.0**이다. `fallback_to_haiku`는 `confidence: haiku_value(:confidence)`(L214)로 **Haiku 결과의 confidence를 그대로 물려받고**, `confidence_to_decimal`은 "medium"→0.75, "low"→0.40, "none"→0.0. 즉 237건 모두 Haiku 결과가 **"none"** 이었다. "none"의 출처는 `LlmRfqAnalyzerService#fallback_result`(API 예외·JSON 파싱 실패 시, L23-27·L192) 또는 모델이 JSON에 literal "none"을 쓴 경우뿐. **LLM 경로 343건 중 medium/low가 0건** — Haiku가 살아서 "애매하다"고 답한 경우가 한 번도 없다는 뜻이고, 이는 literal "none" 237회보다 **Haiku API 실패 237회**가 훨씬 그럴듯하다. 그러면 에스컬레이션 전건이 "Haiku 실패 → Sonnet도 400"이며, 두 모델이 같은 순간 400을 받는 원인은 잔액(Anthropic은 잔액 부족을 HTTP 400으로 반환)이 유일하게 자연스럽다. 04-27 혼재는 **일 단위가 아니라 시각 단위**로 봐야 한다: 20건 성공 뒤 3건 연속 실패면 당일 소진, 섞여 있으면 기각. 메모리 2026-05-08 "토큰 충전했어요"는 반복 충전 패턴과 정합. 키는 04-02 등록 후 무변경(`app_settings` created_at==updated_at)이므로 키 교체로는 구간 전환을 설명할 수 없고, 잔액 변동으로는 설명된다 | **최유력(판별 쿼리 4·5 결과, 부모 실측)**. 쿼리 4: 04-27 fallback 3건은 00:30~02:15, 성공 21건은 05:00~14:30 — **시간대가 완전히 분리**되고 성공 사이에 실패가 끼지 않음 → 02:15~05:00 사이 회복(충전). 쿼리 5: fallback latency min 557ms·avg 1,316ms(Haiku+Sonnet **2회 호출 합**) < haiku 성공 min 1,400ms·avg 2,393ms(1회) → 두 호출 모두 **생성 없이 즉시 거부**. 전 기간 서사: 04-09~04-26 잔액 0 → 04-27 새벽 충전 → 05-01 재소진 → 05-06 재충전 → 05-08 "충전했어요"(메모리). 최종 확정은 400 본문("credit balance")이며, 진단 코드(422-B ⓐ) 배포 후 재개 시점에 자동으로 남는다. 진단은 여기서 멈춘다(대표님 지시 대기) |
| (e) 키의 Sonnet 모델 접근 불가 | 운영 키 = `app_settings.anthropic_api_key`(`sk-ant-api03-…`, 108자, 04-02 등록 후 무변경 — 부모 실측). **키 등록 화면의 검증 호출(`settings/api_keys_controller.rb:31-32`)은 Haiku 4.5로만 검증**하므로 Sonnet이 막힌 키도 "정상" 통과. 04-02 고정 키 + Sonnet 0/237은 정합. **그러나 이 가설은 Haiku까지 "none"(=실패)인 237건을 설명하지 못한다** — 키 접근 문제면 Haiku는 medium/low를 정상 반환했어야 한다 | **차순위.** (d)가 기각될 때만 남는다. E3로 확정 |
| (f) `system` 배열 직렬화 / cache_control 배치 | 스펙(`claude-api` 스킬 ruby README·`shared/prompt-caching.md`): `system`은 `[{type:"text", text:…, cache_control:{type:"ephemeral"}}]` 배열, `cache_control`은 **블록 안**, 브레이크포인트 ≤4 — 코드(L69-83)와 정확히 일치. 두 블록 모두에 붙이는 것도 허용(각각이 브레이크포인트). gem 1.23.0 dump는 `system` 값을 변형 없이 통과(부모도 `system:`/`system_:` 동일 출력 재확인). 코드 주석 "gem 1.23+ 배열 system 지원"의 근거는 gem의 `MessageCreateParams::System` union(String \| Array<TextBlockParam>)이다. 최소 캐시 토큰 미달(SYSTEM_PROMPT ≈200토큰 < Sonnet 4.5 최소 1024)은 **캐시가 안 걸릴 뿐 400이 아니다** | **제외** (스펙·SDK 모두 적합). 단 (d)도 기각되면 E2가 최종 판별 |
| (g) few-shot 문자열의 제어문자·깨진 UTF-8 | Ruby `JSON.generate`는 잘못된 UTF-8이면 **클라이언트에서 `JSON::GeneratorError`를 던진다** → 예외 클래스가 `BadRequestError`일 수 없다. 제어문자는 JSON 이스케이프되어 API가 수용. 게다가 **Haiku 프롬프트도 같은 `few_shot_examples`(limit 5)를 보간**하는데 Haiku는 106건 성공 | **제외** |

**정적 분석의 한계 — Haiku 호출부와 Sonnet 호출부의 실제 diff는 3가지뿐**: ① `system:` 블록 2개(+cache_control) 유무 ② `max_tokens` 1024 vs 2048 ③ 모델 ID. 셋 다 스펙·SDK 안에 있다. 남는 것은 "서버가 왜 400을 줬는가"이며 **400 본문 메시지 없이는 더 못 좁힌다**(L50이 `e.class`만 저장). 테스트도 `call_sonnet_api` 자체를 stub해 요청 형태를 한 번도 검증하지 않았다. 다만 위 (d)의 confidence 논증으로 **"Sonnet만의 결함"이 아니라 "Haiku·Sonnet 동시 실패"가 데이터의 기본형**임은 코드로 확정된다.

**판별 쿼리 4·5 (운영 DB 직접, 컨테이너 불요) — (d) 확정용**
4. `select created_at, model, confidence, latency_ms from classification_logs where model<>'rule-only' and date(created_at) in ('2026-04-27','2026-05-01','2026-05-06') order by created_at;` → 04-27의 fallback 3건이 성공 20건 **뒤에 연속**이면 당일 잔액 소진(=d), 성공 사이에 **끼어** 있으면 Sonnet 고유(=e/f).
5. `select model, count(*), min(latency_ms), avg(latency_ms), max(latency_ms) from classification_logs where model<>'rule-only' group by 1;` → fallback 행 latency가 수백 ms대(400 두 번 = 생성 없음)면 Haiku가 생성조차 못 한 것(=d), 수 초대면 Haiku가 실제로 답을 만든 것(=literal none, e/f 재검토).

**재현 실험 (422-B 첫 작업, 비용 < $0.02, 운영 키 필요)** — dev에서 `AppSetting.set("anthropic_api_key", <운영 키>)` 또는 `ANTHROPIC_API_KEY` 후 `bin/rails runner`:
| 실험 | 요청 | 판정 |
|---|---|---|
| E1 | `SonnetEscalatorService#call_sonnet_api` 그대로 + `rescue Anthropic::Errors::BadRequestError => e; puts e.message` | 400 본문이 곧 답(예: `credit balance`, `model`, `system`, `cache_control` 중 어느 단어가 나오는가) |
| E2 | E1에서 `system:` 제거 | 성공하면 system/cache_control 형태 문제 |
| E3 | E1에서 model만 `claude-haiku-4-5-20251001` | 성공하면 모델 접근(e) 문제 |

~~운영 DB 추가 쿼리~~ → **완료(부모)**: `anthropic_api_key` = `sk-ant-api03-…` 108자, created_at == updated_at = 2026-04-02 09:34 (등록 후 무변경).

**이번 진단의 실제 소득 — 원인이 잔액이면 코드 결함이 아니지만, 시스템은 그것을 알리지 못했다.** RFQ 분류가 18일간 죽어 있었는데 아무도 몰랐다. 전역 규칙 '실패경로 4문항' 위반 3건: ①가짜 채우기(Haiku 실패를 uncertain으로 위장해 rfq_pending으로 흘려보냄) ②무음 실패(reason에 원인 없음) ③사용자 미인지(화면 어디에도 표시 없음). 관제 페이지(ISS-426)의 존재 이유가 정확히 이것이다 — **잔액이 떨어지면 화면에 뜬다.**

**코드 결함 2건(원인과 무관하게 수정 — 진단 코드가 먼저다)**
1. `SonnetEscalatorService#escalate` rescue(L50)가 `reason`에 `e.class`만 남긴다. `e.message` 200자를 함께 저장했다면 이 조사는 쿼리 1건으로 끝났다.
2. `ClassificationOrchestrator#normalize_haiku`(L149-165)가 Haiku 실패(`llm_unavailable: true`, reason "LLM 분석 불가…")를 **confidence "none"으로만 넘기고 실패 사실을 버린다** → Sonnet으로 에스컬레이션되면 로그 행의 reason은 Sonnet 것으로 덮인다. Haiku 실패 여부·사유를 `reason` 접두("stage2_failed:…")나 agent_runs meta에 남겨야 (d)/(e)를 다음부터는 쿼리 1건으로 가른다.
+ 키 검증(`api_keys_controller#verify`)이 Haiku만 호출 → Sonnet 검증 추가(어느 모델이 막혔는지 화면 표시). 부수 관찰(범위 밖): API 키가 `app_settings.value`에 평문 저장 — Lockbox 암호화 후보.

**비용 손실 규모 정정**: Sonnet은 한 번도 성공하지 못했고(실패 호출은 과금 없음) Haiku 성공은 106건 → **운영 기간 실제 LLM 지출 ≈ Haiku 106건분(수십 센트 수준)**. "예산 가드 무력"의 실제 위험은 과거 유출이 아니라 **재개 시점부터 상한 없이 지출된다**는 것. 422-F에서 대표님께 이렇게 설명한다.

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
| **422-A** (ISS-423) | [Agent관제] agent_runs 테이블 + AgentRun.track 헬퍼 + 운영 classification_logs 14,247행 백필 | GENERATE_CODE | P0 | §③ 마이그레이션, `AgentRun` 모델(track/start!/finish!/fallback!/fail!/NullRun, 스코프), `lib/tasks/agent_runs.rake`. 기존 코드 무수정 | ① `schema.rb`에 agent_runs+인덱스 6개. ② 모델 테스트: 블록 예외 → failure 기록 후 재발생 / 쓰기 실패 stub → raise 없이 warn 1회, 블록 반환값 유지. ③ fixture(classification_logs: rule-only·haiku-4.5 cost 0·haiku-4.5-fallback·safety_fallback 각 1 + aqa 1 + rfq_auto 1) rake 2회 → 6행(멱등), 상태 매핑 success/fallback/failure, LLM cost 0 → NULL. ④ 전체 테스트 0 failure. ⑤ **운영에서 1회 실행 → `AgentRun.count == 14,267`, `where(status:"fallback").count == 237`** | — | 4 |
| **422-B** (ISS-424) | [Agent관제] 분류 파이프라인 결함 2건 — Haiku 비용 $0 고정(예산 가드 무력) + Sonnet 에스컬레이션 0/237 BadRequestError | FIX_BUG | **P0** | (1) `LlmRfqAnalyzerService#parse_response`가 `response.usage`(input/output/cache_read)를 파싱해 `cost_usd`·토큰 반환(단가 Haiku 4.5 $1/$5 per MTok — `claude-api` 스킬 표; `SonnetEscalatorService#compute_cost` 패턴 재사용). `normalize_haiku` 무수정. (2) Sonnet 400: 모델 ID·SDK 파라미터·gem 버전·인증 방식·max_tokens·system 형태·few-shot 인코딩은 **제외됨**(§①). 남은 후보 = (d) 잔액 소진(Haiku·Sonnet 동시 400, 최우선) / (e) 키의 Sonnet 접근(차순위). **진단 코드가 먼저다**: ⓐ `escalate` rescue의 reason에 `e.message` 200자 저장 + credit 계열 `AnthropicCreditError` 매핑 통일 + `normalize_haiku`가 Haiku 실패 사실(`llm_unavailable`)을 reason/meta에 보존 ⓑ 키 검증 화면(`api_keys_controller#verify`)에 Sonnet 검증 추가 — 한쪽만 실패해도 어느 모델이 막혔는지 표시 ⓒ 판별 쿼리 4·5(DB 직접) + 배포 후 실제 400 본문 확보 → 원인 확정 ⓓ (d)면 코드 수정 없음 → 422-F 선행 항목 "잔액 확인"; (e)면 키 권한 문제 → 대표님 콘솔 확인 보고; 그 외면 호출부 수정 ⓔ `call_sonnet_api` 요청 형태 검증 테스트 추가(현재는 메서드 전체 stub). **P0 근거**: CostGuard 무력 → 재개 시 상한 없음; 에스컬레이션 전건 실패 = 모호 메일 판정 품질 저하 | ① usage stub → `cost_usd > 0`·토큰 일치; fallback 경로 cost 0 유지; orchestrator 테스트 stage 2 행 `cost_usd > 0`; `cost_guard_test` 통과. ② `BadRequestError("credit balance is too low")` stub → reason에 메시지 포함 + `model: "haiku-4.5-fallback"`, `meta/reason`에 credit 표식(테스트). ③ **운영 로그/DB에서 400 본문 메시지 1건 확보**(reason 컬럼 또는 E1 출력)되어 registry payload에 기록되고 원인이 1개로 확정. ③′ 키 검증이 Haiku·Sonnet 두 모델로 이뤄지고, 한쪽만 실패해도 화면에 어느 모델이 막혔는지 표시된다(컨트롤러 테스트). ③″ Haiku 실패 시 classification_logs.reason에 `stage2_failed:` 접두가 남는다(orchestrator 테스트). ④ 운영 재개 후 첫 에스컬레이션 10건 중 `sonnet-4.5` ≥ 1(0/10이면 재진단). ⑤ S2 CostGuard 게이지 금일 비용 > 0 | 판별 쿼리는 즉시(DB 직접), 코드는 422-A와 독립 | 3 |
| **422-C** (ISS-425) | [Agent관제] 1차 계측 — 분류 미러·RFQ번호 게이트·Rfp 첨부분석·견적첨부·RFQ Auto | GENERATE_CODE | P1 | §③ 표 5경로. 모든 write rescue+warn. Rfp 잡은 부모+자식 2행으로 비용을 처음 저장 | ① 경로별 테스트: 실행 1회당 행수·agent_name·status·cost(Rfp: 부모1+자식2, item_extract cost=`_cost_usd`; rfq_number 메일 → gate 행 1, classify 행 0). ② AgentRun 쓰기 강제 실패 시 본 기능 결과 동일 + warn만. ③ 기존 테스트 회귀 0. ④ 개발서버 칸반 첨부분석 1회 → S4 부모·자식 막대 스크린샷 | 422-A | 4 |
| **422-D** (ISS-426) | [Agent관제] 단일 페이지 /admin/agent_runs — 헤더·상태 스트립·KPI(처리 경로 포함)·에이전트×모델 집계·최근 실행 피드·빈 상태·사이드바 | GENERATE_CODE | **P0** | §② S1·S2·S3·S5 + 빈 상태 + 라우트/컨트롤러(require_admin!)/사이드바/ko·en. 기본 window `all`. brand-dna 토큰. **백필 데이터만으로 완성되는 이슈 — 대표님 첫 화면** | ① 컨트롤러 테스트: admin 200 / manager·member 리다이렉트 / 0행 빈 상태 문구 / window·agent·model·status 필터 / rule-only 13,904·fallback 237 같은 집계값이 fixture 기준으로 정확. ② admin 저니(Playwright 스크린샷 4장): 사이드바 → 페이지(백필 데이터: 처리 경로 타일·에이전트×모델 표·피드) → 필터 → CTA 토스트. ③ brand-guardian 4항목. ④ 페이지 로드 SQL ≤ 12 | 422-A | 6 |
| **422-E** (ISS-427) | [Agent관제] 주문별 타임라인(막대·중첩·폴백/실패) + 실행 상세 패널 (Turbo Frame) | GENERATE_CODE | P1 | §② S4·S6. 백필 데이터로 검증 가능(주문 11,971건 연결). rule-only 행도 표시 | ① `orders/:order_id` 프레임이 해당 주문 run만·부모→자식 순·폭 계산·fallback 색; `show`가 meta(reason·verdict·stage)·error 렌더. ② 저니 스크린샷 3장(펼침 → fallback 행 주황 + reason → 클릭 → 패널). ③ 카드 20개 초기 렌더 시 타임라인 SQL 0회 | 422-D | 4 |
| **422-F** (ISS-428) | [Agent관제] 유입 정지 진단(2026-05-06) + 자동 Gmail sync 재개 결정 [CONFIRM] | FEATURE_PLAN | P1 | (1) 진단(앱 기동 선행): 운영 `EmailAccount`(connected/토큰/refresh_token/last_synced_at) + 컨테이너 로그 `[EmailSyncJob]` warn 유무로 §①-8 (a)/(b) 확정 + **Anthropic 콘솔에서 잔액 확인 + 운영 키(`sk-ant-api03-…`, 04-02 등록)의 Sonnet 4.5 모델 접근 권한 확인**(422-B 판별 결과에 따라 하나가 원인). (2) 결정: 재개 여부·주기. 권고 **"된다"** — 단 **422-B 완료가 선행 조건**. 대표님께 설명할 문장: *"지금까지 새어나간 돈은 Haiku 106건분(수십 센트)뿐이다. 문제는 가드 없이 재개하면 상한이 없다는 것"*. 시작은 하루 2회(09:05·15:05, BusyException 사유). T2 BUDGET → `request-user-confirm.sh`, `payload.requires_user_confirm: true` | ① 정지 원인이 (a)/(b)/(c) 중 하나로 registry에 기록. ② 승인 시 `recurring.yml` 4줄·재인증(필요 시) 후 24h 내 `gmail.classify` 행 ≥ 1, S1 상태 스트립 "자동 동기화: 실행 중". ③ 거부 시 S1 문구 "수동 동기화 운영 중" | 422-B(재개 실행), 진단은 즉시 | 1 |
| **422-G** (ISS-429) | [Agent관제] 2차 계측 확대 — 답변초안·Rfp 분류/긴급초안·분류 stage 자식·RFQ Auto step 자식·insight 잡 | GENERATE_CODE | P2 | usage 파싱 없는 4서비스 산출+기록, `gmail.classify` stage 1/2/3 자식, rfq_auto step 자식, `AgentInsightJob`(kind job, 비용 0). **422-D 화면을 본 뒤 대표님 판단으로 착수** | ① 서비스별 행·cost>0. ② S3에 신규 agent 6개. ③ 회귀 0 | 422-E | 3 |

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

**부모(Opus) 확인 항목 — read-only 운영 쿼리**
1. ~~Sonnet 실패 사유 분포~~ → **완료**: `exception:Anthropic::Errors::BadRequestError` 237/237.
2. ~~판별 쿼리 1·2~~ → **완료**: fallback 237건 confidence 0·uncertain / 04-27 혼재 → 04-27 이후 Sonnet 고유 결함 확정.
3. ~~app_settings 조회~~ → **완료**: `sk-ant-api03-…` 108자, 04-02 등록 후 무변경.
4. **판별 쿼리 4·5(§①, DB 직접)** — 04-27 시각순 배열 + 모델별 latency 분포. (d) 잔액 소진을 확정/기각하는 마지막 데이터 근거.
5. **재현 실험 E1~E3**(§①) — 운영 키를 dev에 넣고 1회(< $0.02). 4·5로 (d)가 확정되면 E1 하나로 충분(400 본문에 "credit balance"가 나오면 종결).
6. 유입 정지 원인(앱 기동 후): `select id, email, connected, last_synced_at, gmail_token_expires_at, (refresh_token is not null) from email_accounts;` + `kamal app logs | grep "\[EmailSyncJob\]"` → 422-F 진단. **지금 단계에서는 보류**(컨테이너 정지).
7. ~~디자인 토큰~~ → **확정**: brand-dna `#166c72`.

**범위 밖 발견(별도 이슈 후보)**: `Rfp::AnalyzeAttachmentsJob#bump_opus_counter`의 런타임 registry.json 직접 쓰기 → agent_runs 도입 후 제거(REFACTOR). 운영 컨테이너 정지·도메인 타 프로젝트 서빙은 부모 인프라 이슈(본 기획은 "앱이 떠 있어야 운영 확인 가능" 의존성만 인지).

**더 하면 좋은 것**: `AgentRun after_create_commit → Turbo Stream prepend`로 S5 실시간(≈1h) / 주문 드로어에 "AI 판정 근거" 링크(S6 재사용, 고객 설명용) / 에이전트별 예산 게이트는 기존 CostGuard 대체가 아닌 신규 추가로.
