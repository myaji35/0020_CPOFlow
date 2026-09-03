# frozen_string_literal: true

module Gmail
  # ISS-045 Phase C: 3단 필터 파이프라인 조정자
  #
  # Stage 0: Ariba/자사/노이즈 사전 제외 (RfqDetectorService 재사용)
  # Stage 1: Gmail::Stage1::RuleGate — 규칙 기반 whitelist/약신호/reject
  # Stage 2: Gmail::LlmRfqAnalyzerService — Haiku 4.5
  # Stage 3: Gmail::SonnetEscalatorService — Sonnet 4.5 (confidence < high 시)
  #
  # 반환: Gmail::ClassificationResult
  # 부가 효과: classification_logs INSERT (stage별 latency/cost 포함)
  #
  # Fallback (Plan §4.3 — Recall 우선):
  #   - Sonnet API error → Haiku 결과 채택, reason에 "stage3_fallback_to_stage2"
  #   - Stage 2 JSON parse fail → uncertain → rfq_pending 저장 경로
  #   - 모든 fallback 실패 → safety_fallback (uncertain, Recall 우선 표시)
  #
  # Usage:
  #   result = Gmail::ClassificationOrchestrator.new(parsed_email).classify
  #   result.verdict            # => :confirmed | :excluded | :uncertain
  #   result.stage_reached      # => 0 | 1 | 2 | 3
  #   result.classifier_version # => "v2"
  class ClassificationOrchestrator
    CLASSIFIER_VERSION = "v2"

    # ISS-056: 호출자가 특정 로그 row만 타겟할 수 있도록 마지막 로그 ID 노출
    attr_reader :last_log_id

    def initialize(parsed_email, order: nil)
      @email     = parsed_email
      @order     = order # 있으면 log에 연결, 없으면 nil (pre-create 경로)
      @stage1_ms = nil
      @stage2_ms = nil
      @stage3_ms = nil
      @last_log_id = nil
    end

    # @return [Gmail::ClassificationResult]
    def classify
      # --- Stage 0 ---
      stage0 = run_stage0
      return log_and_return(stage0) if stage0

      # --- Stage 1 ---
      t1 = Time.now
      gate = Gmail::Stage1::RuleGate.decide(@email)
      @stage1_ms = ((Time.now - t1) * 1000).to_i

      case gate.action
      when :reject_no_signal
        # Recall 우선 정책: 신호 없는 메일도 uncertain으로 수신
        # Stage 0에서 뉴스레터/자사도메인은 이미 제외됨. 여기 도달한 메일은 모호한 건.
        return log_and_return(build_stage1_uncertain(gate))
      when :whitelist_fast, :pass_to_llm
        # fall through to Stage 2
      end

      # --- Stage 2 (Haiku) ---
      t2 = Time.now
      haiku_hash = Gmail::LlmRfqAnalyzerService.new(@email).analyze
      @stage2_ms = ((Time.now - t2) * 1000).to_i

      haiku_result = normalize_haiku(haiku_hash)

      # Haiku confidence == "high" 이면 Stage 2에서 확정
      return log_and_return(haiku_result) if haiku_result.confidence == "high"

      # --- Stage 3 (Sonnet 에스컬레이션) ---
      t3 = Time.now
      sonnet_result = Gmail::SonnetEscalatorService.new(@email, haiku_result).escalate
      @stage3_ms = ((Time.now - t3) * 1000).to_i

      # SonnetEscalatorService는 이미 Gmail::ClassificationResult 반환
      log_and_return(sonnet_result)
    rescue StandardError => e
      Rails.logger.error "[ClassificationOrchestrator] fatal: #{e.class} — #{e.message}"
      # Recall 우선: 예상 외 예외 시 uncertain 반환 (rfq_pending 경로)
      log_and_return(safety_fallback(e))
    end

    private

    # Stage 0: 조기 제외 (Ariba는 confirmed로 확정). RfqDetectorService 내부 로직 재사용.
    # @return [Gmail::ClassificationResult, nil] 제외/확정이면 결과, 아니면 nil (pass-through)
    def run_stage0
      detector = Gmail::RfqDetectorService.new(@email)

      if detector.send(:ariba_sender?)
        return Gmail::ClassificationResult.new(
          verdict: :confirmed, is_rfq: true, confidence: "high",
          stage_reached: 0, classifier_version: CLASSIFIER_VERSION,
          reason: "stage0_ariba_sender",
          extracted: {}, cost_usd: 0.0, latency_ms: 0, cache_hit: false,
          model: "rule-only"
        )
      end

      if detector.send(:own_sender?)
        return Gmail::ClassificationResult.new(
          verdict: :excluded, is_rfq: false, confidence: "high",
          stage_reached: 0, classifier_version: CLASSIFIER_VERSION,
          reason: "stage0_own_sender",
          extracted: {}, cost_usd: 0.0, latency_ms: 0, cache_hit: false,
          model: "rule-only"
        )
      end

      if detector.send(:excluded_sender?) || detector.send(:excluded_subject?)
        return Gmail::ClassificationResult.new(
          verdict: :excluded, is_rfq: false, confidence: "high",
          stage_reached: 0, classifier_version: CLASSIFIER_VERSION,
          reason: "stage0_excluded_pattern",
          extracted: {}, cost_usd: 0.0, latency_ms: 0, cache_hit: false,
          model: "rule-only"
        )
      end

      nil
    end

    def build_stage1_excluded(gate_result)
      Gmail::ClassificationResult.new(
        verdict: :excluded, is_rfq: false, confidence: "high",
        stage_reached: 1, classifier_version: CLASSIFIER_VERSION,
        reason: "stage1_#{gate_result.reason}",
        extracted: {}, cost_usd: 0.0, latency_ms: @stage1_ms || 0,
        cache_hit: false, model: "rule-only"
      )
    end

    # Recall 우선: 신호 없는 메일도 uncertain으로 수신 (모호한 건 = 수신)
    def build_stage1_uncertain(gate_result)
      Gmail::ClassificationResult.new(
        verdict: :uncertain, is_rfq: nil, confidence: "low",
        stage_reached: 1, classifier_version: CLASSIFIER_VERSION,
        reason: "stage1_no_signal_but_recall_priority",
        extracted: {}, cost_usd: 0.0, latency_ms: @stage1_ms || 0,
        cache_hit: false, model: "rule-only"
      )
    end

    # Hash → Gmail::ClassificationResult (Stage 2 기본 변환)
    def normalize_haiku(haiku_hash)
      haiku_hash ||= {}
      verdict = case haiku_hash[:verdict] || haiku_hash[:rfq_verdict]
      when :confirmed, "confirmed" then :confirmed
      when :excluded, "excluded"   then :excluded
      when :uncertain, "uncertain" then :uncertain
      else
                  haiku_hash[:is_rfq] ? :confirmed : :uncertain
      end

      Gmail::ClassificationResult.new(
        verdict: verdict,
        is_rfq: haiku_hash[:is_rfq],
        confidence: haiku_hash[:confidence] || "low",
        stage_reached: 2,
        classifier_version: CLASSIFIER_VERSION,
        reason: ((haiku_hash[:llm_unavailable] ? "stage2_failed: " : "") + (haiku_hash[:reason].to_s.presence || "stage2_haiku")).first(500),
        extracted: haiku_hash[:extracted] || build_extracted_from_hash(haiku_hash),
        cost_usd: haiku_hash[:cost_usd].to_f,
        latency_ms: @stage2_ms || 0,
        cache_hit: haiku_hash[:cache_hit] || false,
        model: "haiku-4.5"
      )
    end

    # LlmRfqAnalyzerService 는 flat hash를 반환 → extracted 필드로 합치기 (없으면 비움)
    def build_extracted_from_hash(h)
      {
        customer_name:     h[:customer_name],
        due_date:          h[:due_date],
        items:             h[:items] || [],
        quantities:        h[:quantities] || [],
        project_name:      h[:project_name],
        delivery_location: h[:delivery_location],
        currency:          h[:currency],
        estimated_value:   h[:estimated_value],
        urgency:           h[:urgency]
      }.compact
    end

    def safety_fallback(error)
      Gmail::ClassificationResult.new(
        verdict: :uncertain, is_rfq: nil, confidence: "none",
        stage_reached: 0, classifier_version: CLASSIFIER_VERSION,
        reason: "safety_fallback:#{error.class}",
        extracted: {}, cost_usd: 0.0, latency_ms: 0, cache_hit: false,
        model: "rule-only"
      )
    end

    def log_and_return(result)
      log = ClassificationLog.create!(
        order_id:           @order&.id,
        email_message_id:   @email[:message_id] || @email[:id],
        classifier_version: result.classifier_version,
        stage_reached:      result.stage_reached,
        verdict:            result.verdict.to_s,
        is_rfq:             result.is_rfq,
        confidence:         confidence_to_decimal(result.confidence),
        would_exclude:      false, # ISS-053 EmailSyncJob에서 true로 overwrite 가능
        reason:             result.reason.to_s.first(500),
        cost_usd:           result.cost_usd || 0.0,
        latency_ms:         total_latency_ms(result),
        cache_hit:          result.cache_hit || false,
        model:              result.model
      )
      @last_log_id = log.id # ISS-056: 특정 row ID 캡처 (재시도/병렬 오염 방지)
      begin
        started = Time.current - (total_latency_ms(result) / 1000.0)
        AgentRun.create!(
          agent_name: "gmail.classify", kind: "service", status: agent_run_status_for(result),
          started_at: started, finished_at: Time.current, duration_ms: total_latency_ms(result),
          model: result.model, order_id: @order&.id,
          cost_usd: (result.model.to_s.start_with?("rule-only") ? nil : result.cost_usd),
          source_type: "ClassificationLog", source_id: log.id,
          meta: { verdict: result.verdict, stage_reached: result.stage_reached,
                  reason: result.reason.to_s.first(300), confidence: result.confidence,
                  cache_hit: result.cache_hit }.to_json.first(4096)
        )
      rescue StandardError => e
        Rails.logger.warn "[AgentRun] gmail.classify mirror failed: #{e.class}: #{e.message.to_s.first(200)}"
      end
      result
    rescue StandardError => e
      Rails.logger.warn "[ClassificationOrchestrator] log insert failed: #{e.class} — #{e.message}"
      result
    end

    def total_latency_ms(result)
      stage_sum = (@stage1_ms || 0) + (@stage2_ms || 0) + (@stage3_ms || 0)
      stage_sum.positive? ? stage_sum : (result.latency_ms || 0)
    end

    def agent_run_status_for(result)
      reason = result.reason.to_s
      return "fallback" if reason.start_with?("stage3_fallback_to_stage2", "credit_exhausted", "stage2_failed")
      return "failure" if reason.start_with?("safety_fallback", "stage3_total_failure")

      "success"
    end

    # "high"/"medium"/"low"/"none" → 0.0..1.0 decimal
    def confidence_to_decimal(conf)
      case conf.to_s
      when "high"   then 0.95
      when "medium" then 0.75
      when "low"    then 0.40
      else               0.0
      end
    end
  end
end
