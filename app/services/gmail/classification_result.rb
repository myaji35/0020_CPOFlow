# frozen_string_literal: true

module Gmail
  # ISS-045 Phase A: 3단 필터 공통 결과 Value Object
  #
  # Stage 1 (RuleGate) / Stage 2 (Haiku) / Stage 3 (Sonnet) 모두 동일한 형태로 반환.
  # Shadow Mode 기간 방식 2(사용자 판정)와 비교를 위해 classification_logs에 저장.
  #
  # Usage:
  #   Gmail::ClassificationResult.new(
  #     verdict: :confirmed, is_rfq: true, confidence: "high",
  #     stage_reached: 2, classifier_version: "v2",
  #     reason: "whitelist domain + strong keyword",
  #     extracted: { customer_name: "KEPCO" },
  #     cost_usd: 0.0013, latency_ms: 450, cache_hit: true,
  #     model: "claude-haiku-4-5-20251001"
  #   )
  ClassificationResult = Data.define(
    :verdict,             # Symbol: :confirmed | :excluded | :uncertain
    :is_rfq,              # Boolean | nil (uncertain 시 nil 가능)
    :confidence,          # String: "high" | "medium" | "low" | "none" (v1 호환)
    :stage_reached,       # Integer: 1 | 2 | 3
    :classifier_version,  # String: "v1" | "v2"
    :reason,              # String (max 500자)
    :extracted,           # Hash (customer_name, items, ...)
    :cost_usd,            # Float
    :latency_ms,          # Integer
    :cache_hit,           # Boolean
    :model                # String: "rule-only" | "haiku-4.5" | "sonnet-4.5"
  ) do
    # Haiku confidence == "high" 이면 자동 확정, 그 외는 Sonnet 에스컬레이션
    def confirmed_by_haiku?
      stage_reached == 2 && confidence == "high" && verdict == :confirmed
    end

    def escalate_to_sonnet?
      stage_reached == 2 && confidence != "high"
    end

    # Cutover 이후 사용자 화면 노출 안전 여부 (Recall 우선)
    def safe_for_cutover?
      verdict == :confirmed || verdict == :excluded
    end

    def to_log_hash
      {
        verdict: verdict.to_s,
        is_rfq: is_rfq,
        confidence: confidence,
        stage_reached: stage_reached,
        classifier_version: classifier_version,
        reason: reason.to_s.first(500),
        cost_usd: cost_usd,
        latency_ms: latency_ms,
        cache_hit: cache_hit,
        model: model
      }
    end
  end
end
