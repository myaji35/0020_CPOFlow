# FEATURE PLAN: email-classify-v2 (ISS-045 / ISS-049 revision)

> **Version**: 1.1 (ISS-049 Revision)
> **Status**: READY_FOR_IMPLEMENTATION (CEO APPROVE_WITH_CHANGES + Eng NEEDS_REVISION 반영 완료)
> **Author**: product-manager (harness)
> **Created**: 2026-04-09
> **Parent**: ISS-045
> **Related**: ISS-047 (recall-safety), ISS-048 (PoC), ISS-050 (SQLite hotfix)

---

## Revision Log

| Version | 변경 | Trigger |
|---|---|---|
| 1.0 | 초안 (3단 필터 + Shadow Mode 7일 + Golden Dataset 200) | product-manager opus |
| **1.1** | 본 revision | CEO 87점 APPROVE_WITH_CHANGES + Eng 58점 NEEDS_REVISION + ISS-048 PoC 결과 |

### v1.1 주요 변경점
1. **Golden Dataset 200 → 250건** (최근 6개월 데이터 70% 가중)
2. **US-045-5 경량화**: 별도 대시보드 → Admin 기존 페이지 카드 3개
3. **Shadow Mode Day3 중간 게이트** 추가 (비용/Recall 이상 시 즉시 중단)
4. **Stage 1 RuleGate PORO 추출** — v1/v2 공유 모듈화
5. **ClassificationResult Value Object** 정의
6. **Order 신규 컬럼 명시** (classifier_version, stage_reached, stage1/2/3_latency_ms, cache_hit)
7. **Stage 3 Sonnet 실패 시 fallback path** 명시 (Haiku 결과 채택)
8. **과거 Order freeze 규칙** 명시 (cutover 시 기존 rfq_status 덮어쓰기 금지)
9. **SQLite busy_timeout=5000 선결** — ISS-050 hotfix 선행
10. **Sonnet 에스컬레이션 비율**: 30% 가정 → production 실측 후 재추정 (Shadow Day 3)
11. **일정**: 12.5일 → **18일** 현실화
12. **CEO 5개 답변 Plan 내 확정** (Open Questions 섹션 제거)

---

## 1. Overview

### 1.1 Context
CPOFlow 견적 메일 분류 파이프라인의 Recall 누락 사고(2026-03 KEPCO 이메일 누락) 재발 방지. 현재 `RfqDetectorService` + `LlmRfqAnalyzerService`(Haiku 단독)로 판정 중.

### 1.2 Goal (확정)
- **Recall ≥ 99.5%** (Golden Dataset 250건 기준, CEO 확정)
- **일 비용 ≤ $0.30** (Shadow Day 3 재추정 후 확정)
- **Shadow Mode 7일 + 최소 300건 분류 중 늦은 것** (Eng 피드백 반영)
- **FN 0건** (7일 누적, Shadow 기간)

### 1.3 Non-goals
견적서 자동 작성, 답변 톤 학습, 다국어 OCR, Gmail Push Notification.

---

## 2. Success Metrics (확정)

| Metric | Baseline | Target | 측정 | 비고 |
|---|---|---|---|---|
| Recall | ~0.94 (추정) | **≥ 0.995** | Golden 250건 회귀 | CEO 확정 |
| Precision | 0.85 | ≥ 0.85 유지 | Golden 250건 | |
| 일 LLM 비용 | ~$0.85 | **≤ $0.30** | API usage 로그 | Shadow D3 재계산 |
| Shadow FN | N/A | **0건 / 7일** | classification_logs diff | |
| Latency p95 | ~1.2s | ≤ 2.5s | EmailSyncJob 메트릭 | |
| 담당자 수동 검수 | 1.5h/day | ≤ 0.2h/day | Inbox 액션 로그 | |

---

## 3. CEO 확정 답변 (Open Questions 제거)

| Q | 답변 |
|---|---|
| Cutover 기준 숫자 | Recall ≥ 99.5% AND 일 비용 ≤ $0.30 AND FN 0건 (7일 OR 300건 중 늦은 것). 하나라도 미달 시 1주 연장 |
| Golden Dataset 규모 | 250건 (confirmed 100 + excluded 100 + 모호 50), 최근 6개월 70% 가중 |
| Sonnet 에스컬레이션 트리거 | Haiku confidence < 0.85 OR uncertain 전부. 예산 내 공격적 호출 |
| Admin 대시보드 MVP | 경량화 — 기존 `/admin` 페이지에 카드 3개만 (일 비용 / Stage 분기율 / 최근 FN 케이스) |
| Shadow FN 발견 시 | 담당자 즉시 수동 재분류 → Golden Dataset에 추가 → v2 프롬프트 튜닝 트리거 → runbook 문서화 |

---

## 4. Eng Critical 대응 (v1.1 핵심)

### 4.1 Stage 1 RuleGate 공유 모듈 추출 (Must-Fix #1)

기존 `RfqDetectorService#detect`의 private 메서드 6개(`own_sender?`, `excluded_sender?`, `excluded_subject?`, `ariba_sender?`, `keyword_match`, `body_score`)를 **PORO로 추출**하여 v1/v2 모두 호출 가능하게 한다.

```ruby
# app/services/gmail/stage1/rule_gate.rb (신규)
module Gmail::Stage1
  class RuleGate
    WHITELIST_DOMAINS = Set.new(%w[
      adnoc.ae kepco.co.kr samsungeng.com hyundai-eng.com
      qatarrail.qa neom.sa shapoorji.ae aldarproperties.ae
      enec.gov.ae pcfc.ae ariba.com ansmtp.ariba.com
    ]).freeze

    STRONG_RFQ_KEYWORDS = [
      /\brfq\b/i, /request for quot/i, /\btender\b/i, /\brfp\b/i,
      /견적\s*요청/, /견적\s*의뢰/, /입찰요청/, /طلب\s*عرض/, /طلب\s*تسعير/
    ].freeze

    WEAK_SIGNALS = [
      /\b(sika|monotop|viscocrete|sikadur|sikaflex|sikagrout)/i,
      /\b(waterproofing|concrete|epoxy|sealant|grout|admixture)/i,
      /\d+\s*(kg|ton|cartridge|drum|pcs|set|meter|m2|m3)/i,
      /\b(USD|AED|KRW|SAR|QAR)\b/,
      /납기|단가|물량|공급/
    ].freeze

    Result = Data.define(:action, :reason, :signals)
    # action: :pass_to_llm | :reject_no_signal | :whitelist_fast

    def self.decide(parsed_email)
      new(parsed_email).decide
    end

    def initialize(email)
      @email = email
      @domain = extract_domain(email[:from])
    end

    def decide
      return Result.new(:whitelist_fast, "whitelist_domain", [@domain]) if whitelist?

      strong = STRONG_RFQ_KEYWORDS.select { |r| match?(r) }
      weak   = WEAK_SIGNALS.select { |r| match?(r) }

      if strong.any?
        Result.new(:pass_to_llm, "strong_keyword", strong.map(&:source))
      elsif weak.any?
        Result.new(:pass_to_llm, "weak_signal", weak.map(&:source))
      else
        Result.new(:reject_no_signal, "no_rfq_signal", [])
      end
    end

    private

    def whitelist?
      WHITELIST_DOMAINS.include?(@domain) || dynamic_whitelist.include?(@domain)
    end

    def dynamic_whitelist
      Rails.cache.fetch("rule_gate/dynamic_whitelist", expires_in: 1.day) do
        Set.new(RfqFeedback.where(verdict: "confirmed")
                           .group(:sender_domain)
                           .having("count(*) >= 3")
                           .pluck(:sender_domain))
      end
    end

    def extract_domain(from)
      from.to_s.match(/@([^>\s]+)/)&.[](1)&.strip&.downcase
    end

    def match?(regex)
      "#{@email[:subject]} #{@email[:body].to_s.first(4000)}".match?(regex)
    end
  end
end
```

### 4.2 ClassificationResult Value Object (Must-Fix #2)

```ruby
# app/services/gmail/classification_result.rb
module Gmail
  ClassificationResult = Data.define(
    :verdict,             # :confirmed | :excluded | :uncertain
    :is_rfq,              # true | false | nil
    :confidence,          # 0.0..1.0
    :stage_reached,       # 1 | 2 | 3
    :classifier_version,  # "v1" | "v2"
    :reason,
    :extracted,           # Hash (customer_name, items, ...)
    :cost_usd,            # Float
    :latency_ms,          # Integer
    :cache_hit,           # Boolean
    :model                # "rule-only" | "haiku-4.5" | "sonnet-4.5"
  ) do
    def confirmed? = verdict == :confirmed
    def escalate_to_sonnet? = stage_reached == 2 && confidence < 0.85
    def safe_for_cutover? = confidence >= 0.85 || verdict == :excluded
  end
end
```

### 4.3 Stage 3 Fallback Path (Critical #4)

```
Stage 3 Sonnet 호출
├── 성공 → 결과 반환 (verdict 확정)
├── API 에러 (timeout/rate_limit) → **Haiku 결과 채택 (Stage 2 result로 degrade)**
│   └── classification_log에 "stage3_fallback_to_stage2" 기록
├── JSON parse 에러 → **uncertain으로 classify → rfq_uncertain 상태로 저장**
│   └── 담당자 수동 확인 큐로 이동 (ISS-047과 연동)
└── 모든 fallback 실패 → confirmed로 판정 (Recall 우선, 안전 측 실수)
```

**원칙**: Sonnet은 최종 결정자이므로 실패 시에도 **Recall 방향으로 기울임**. "놓치는 실수"보다 "오탐 실수"를 허용.

### 4.4 Order 신규 컬럼 (Must-Fix #3)

```ruby
# db/migrate/20260410000001_add_classifier_fields_to_orders.rb
class AddClassifierFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :classifier_version, :string, default: "v1"
    add_column :orders, :stage_reached,       :integer
    add_column :orders, :stage1_latency_ms,   :integer
    add_column :orders, :stage2_latency_ms,   :integer
    add_column :orders, :stage3_latency_ms,   :integer
    add_column :orders, :classification_confidence, :decimal, precision: 5, scale: 4
    add_column :orders, :cache_hit,           :boolean, default: false

    add_index :orders, :classifier_version
    add_index :orders, [:classifier_version, :created_at]
  end
end
```

### 4.5 과거 Order Freeze 규칙 (Must-Fix #9)

**v2 cutover 이후, 기존 Order의 `rfq_status` / `classifier_version`은 절대 덮어쓰지 않는다.**
- 신규 insert된 Order만 `classifier_version: "v2"`로 표기
- 과거 Order는 `classifier_version: "v1"` 영구 보존
- 재분류가 필요한 경우 별도 rake task로 명시적 수동 실행 (`classify:recompute[order_id]`)

### 4.6 SQLite busy_timeout 선결 (PoC #3)

**ISS-050 hotfix로 분리**. `config/database.yml` 에 `timeout: 5000` 추가 후 Shadow Mode 시작 전 배포 필수.

```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000          # ← ISS-050
  pragmas:
    journal_mode: wal
    synchronous: normal
    busy_timeout: 5000   # ← ISS-050
```

### 4.7 Golden Dataset 수집 — 프로덕션 전용 (PoC #2)

**로컬 dev DB에는 데이터 부족** (rfq_triage=1, rfq_excluded=0). 수집은 **프로덕션 서버에서만**:

```ruby
# lib/tasks/golden_dataset.rake
namespace :golden do
  desc "프로덕션 DB에서 Golden Dataset 250건 수집"
  task collect: :environment do
    confirmed = Order.where(rfq_status: :rfq_triage)
                     .where("created_at >= ?", 180.days.ago)
                     .order("RANDOM()")
                     .limit(100)
    excluded  = Order.where(rfq_status: :rfq_excluded)
                     .where("created_at >= ?", 180.days.ago)
                     .order("RANDOM()")
                     .limit(100)
    uncertain = Order.where(rfq_status: :rfq_pending)
                     .where("classification_confidence BETWEEN 0.5 AND 0.85")
                     .order("RANDOM()")
                     .limit(50)

    # 최근 6개월 가중: 90일 이내 70% 비중
    # (implementation: partition + sample)

    export_yaml(confirmed, "confirmed")
    export_yaml(excluded, "excluded")
    export_yaml(uncertain, "uncertain")
  end
end
```

**실행**: `kamal app exec "bin/rails golden:collect"` → YAML 파일을 `git add` 후 커밋.

### 4.8 prompt caching 적용 샘플 (PoC #1)

```ruby
# anthropic gem 1.23.0 기준
client.messages.create(
  model: "claude-sonnet-4-5-20250929",
  max_tokens: 2048,
  system: [
    { type: "text", text: SYSTEM_PROMPT,
      cache_control: { type: "ephemeral" } },   # ← 시스템 프롬프트 캐싱
    { type: "text", text: FEW_SHOTS_20,
      cache_control: { type: "ephemeral" } }    # ← few-shot 캐싱
  ],
  messages: [{ role: "user", content: email_body }]
)
```
**비용 효과**: 캐시 HIT 시 input 토큰 90% 할인. Shadow Day 1에 `_usage.cache_creation_input_tokens` / `_usage.cache_read_input_tokens` 필드로 실측.

---

## 5. 3단 필터 아키텍처 (v1.0 동일, 요약만)

```
Inbound Email → Stage 0 (즉시 제외: Ariba/자사/노이즈)
             → Stage 1 (RuleGate: whitelist_fast / pass_to_llm / reject_no_signal)
             → Stage 2 (Haiku 4.5): confidence high → 확정, medium/low → Stage 3
             → Stage 3 (Sonnet 4.5): 최종 판정 (uncertain 반환 금지)
             → Order.rfq_status 저장 + classification_log 기록
```

**비용 시뮬레이션 (prompt caching 적용 후)**:
- Haiku 84통 × $0.0013 ≈ $0.11/일
- Sonnet 18통 × $0.0083 ≈ $0.15/일
- **합계 $0.26/일 = $7.8/월** (목표 $0.30 대비 13% 여유)

---

## 6. User Stories (6개, v1.1 수정)

| ID | 제목 | 변경 | 의존성 |
|---|---|---|---|
| US-045-1 | Stage 1 RuleGate PORO 구현 + 단위테스트 30건 | PORO 추출로 스코프 확장 | 없음 |
| US-045-2 | Stage 3 SonnetEscalatorService + fallback path | fallback 명시 추가 | 없음 |
| US-045-3 | classification_logs + Shadow orchestrator + EmailSyncJob 통합 | Order 신규 컬럼 추가 | US-045-1,2 |
| US-045-4 | Golden Dataset 250 수집 (production) + CI 회귀 | 200→250, production 전용 | US-045-3 |
| US-045-5 | Admin 기존 페이지 카드 3개 (경량화) | 별도 대시보드 → 카드만 | US-045-3 |
| US-045-6 | verify_v2_ready + cutover + v1 deprecation | day3 중간 게이트 추가 | US-045-1~5 |

---

## 7. Phase (v1.1 일정 — 18일)

| Phase | 내용 | 기간 | 병렬 |
|---|---|---|---|
| **Phase A** | Stage 1 RuleGate PORO + 단위 테스트 | 2일 | Yes (B와) |
| **Phase B** | Stage 3 Sonnet + fallback + prompt caching | 3일 | Yes (A와) |
| **Phase C** | Migration + orchestrator + EmailSyncJob 통합 + Shadow 인프라 | 3일 | A,B 후 |
| **Phase D** | Golden Dataset 250 수집 (prod) + CI 회귀 | 2일 | C 후 |
| **Phase E** | Admin 카드 3개 + 모니터링 | 1일 | C 후 (D와 병렬) |
| **Phase F** | Shadow Mode 운영 7일 OR 300건 (늦은 것) + day3 게이트 | 7일 | D,E 후 |
| **Phase G** | cutover + v1 deprecation + 고객 공지 초안 | 1일 | F 통과 후 |

**총 18일** (코딩 11일 + 운영 7일), ISS-050 hotfix 선행.

---

## 8. Shadow Mode Day 3 중간 게이트 (신규)

```
Shadow Day 3 자동 실행: bin/rails email_classify:day3_check
  ├── 일 평균 비용 > $0.35 → 🚨 중단, Stage 2 임계값 재조정
  ├── Sonnet 에스컬레이션 비율 > 50% → 🚨 중단, Stage 1 화이트리스트 확장
  ├── v1↔v2 불일치 > 10% → 🚨 중단, 원인 분석
  ├── API 에러율 > 5% → 🚨 중단
  └── 모두 정상 → 🟢 Day 7까지 진행
```

중단 시 자동 Slack 알림 (ISS-036 완료 후) + 대표님 confirm 절차.

---

## 9. Risks & Mitigation (v1.1)

| R | Risk | Mitigation |
|---|---|---|
| R1 | SQLite busy lock | ISS-050 busy_timeout=5000 선행 |
| R2 | Golden Dataset 수집 실패 | 프로덕션 DB 확인 후 규모 조정, 부족하면 수동 라벨링 50건 추가 |
| R3 | prompt caching 비용 효과 미달 | Shadow Day 1 실측 후 재계산, 목표 초과 시 Stage 1 확장 |
| R4 | Sonnet 에스컬레이션 50% 초과 | Day 3 게이트에서 자동 중단 + Haiku 임계값 조정 |
| R5 | Plan 핑퐁 (meta-agent 감지) | v1.1 이후 revision 금지, 실측 데이터 기반 조정만 |
| R6 | 과거 Order 덮어쓰기 사고 | migration + 코드에 freeze 규칙 명시 |

---

## 10. Definition of Ready
- [x] CEO APPROVE (87점) — 변경사항 v1.1에 반영 완료
- [x] Eng NEEDS_REVISION 대응 — 9 Must-Fix 전부 v1.1에 반영
- [x] PoC 3건 완료 (ISS-048)
- [ ] ISS-050 SQLite hotfix 배포 (Phase A 시작 전 필수)

---

## 11. Related Files
- `app/services/gmail/llm_rfq_analyzer_service.rb` (Stage 2 재사용)
- `app/services/gmail/rfq_detector_service.rb` (Stage 0 로직 공유, v1.1에서 RuleGate 추출)
- `app/services/gmail/rfq_feedback_service.rb` (few-shot + 화이트리스트 동적 소스)
- `app/jobs/email_sync_job.rb` (Shadow Mode 분기 추가 대상)
- `Gemfile` (anthropic 1.23.0)
- `config/database.yml` (ISS-050 선행)

---

**Verdict**: READY_FOR_IMPLEMENTATION (ISS-050 hotfix 선행 조건부)
**Next**: ISS-050 긴급 hotfix → Phase A/B 병렬 GENERATE_CODE 이슈 spawn
