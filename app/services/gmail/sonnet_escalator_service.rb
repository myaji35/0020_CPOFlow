# frozen_string_literal: true

module Gmail
  # ISS-045 Phase B: Stage 3 Sonnet 에스컬레이션
  #
  # 목적: Haiku(Stage 2)가 confidence != "high" 로 모호하게 판정한 메일을
  # 더 큰 컨텍스트(본문 8000자) + few-shot 20건 + Haiku 응답을 함께 넣고
  # Sonnet 4.5로 최종 판정.
  #
  # Fallback path (Recall 우선 — 놓치는 실수보다 오탐 허용):
  #   Sonnet API success → Sonnet 결과 채택
  #   Sonnet API error   → Haiku 결과 채택 (degrade to stage 2)
  #   Haiku 결과도 없음  → confirmed 처리 (Recall 우선)
  #
  # prompt caching (anthropic gem 1.23+):
  #   system + few-shot 블록에 cache_control: { type: "ephemeral" } 적용
  #   → 동일 system/few-shot 반복 호출 시 input 토큰 90% 할인
  #
  # Usage:
  #   result = Gmail::SonnetEscalatorService.new(parsed_email, haiku_result).escalate
  #   result.class        # => Gmail::ClassificationResult
  #   result.stage_reached # => 3
  #   result.model        # => "sonnet-4.5" or "haiku-4.5" (fallback)
  class SonnetEscalatorService
    MAX_BODY_CHARS = 8000  # Haiku보다 2배 큰 컨텍스트
    FEW_SHOT_LIMIT = 20    # Haiku는 5건, Sonnet은 20건
    DEFAULT_MODEL  = "claude-sonnet-4-5-20250929"

    SONNET_INPUT_PER_1M  = 3.0   # USD
    SONNET_OUTPUT_PER_1M = 15.0  # USD

    def initialize(parsed_email, haiku_result)
      @email = parsed_email
      @haiku = haiku_result  # Gmail::ClassificationResult (stage_reached: 2) or Hash (v1 호환)
    end

    # @return [Gmail::ClassificationResult]
    def escalate
      t0 = Time.now
      response = call_sonnet_api
      return fallback_to_haiku(reason: "api_returned_nil") if response.nil?

      parsed = parse_response(response)
      return fallback_to_haiku(reason: "parse_failed") if parsed.nil?

      latency = ((Time.now - t0) * 1000).to_i
      build_result(parsed, latency: latency, response: response)
    rescue StandardError => e
      Rails.logger.warn "[SonnetEscalator] API error: #{e.class} — #{e.message}"
      fallback_to_haiku(reason: "exception:#{e.class}")
    end

    private

    def call_sonnet_api
      client = ClaudeTokenResolver.create_client
      return nil unless client

      client.messages.create(
        model:      ENV.fetch("RFQ_SONNET_MODEL", DEFAULT_MODEL),
        max_tokens: 2048,
        system:     build_system_blocks,
        messages:   [ { role: "user", content: build_user_prompt } ]
      )
    end

    # system 블록에 prompt caching 적용
    # anthropic gem 1.23+ 는 배열 형태 system 블록을 지원
    def build_system_blocks
      few_shots_text = build_few_shots_text

      blocks = [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" }
        }
      ]
      if few_shots_text.present?
        blocks << {
          type: "text",
          text: few_shots_text,
          cache_control: { type: "ephemeral" }
        }
      end
      blocks
    end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a senior procurement specialist at AtoZ2010, a B2B supplier of construction materials
      (Sika waterproofing, concrete admixtures, adhesives, sealants, grouts) to large infrastructure
      projects in the Middle East (UAE, Saudi Arabia, Qatar) and South Korea (KEPCO, Samsung Eng, etc).

      You are the FINAL stage of a 3-stage email classification pipeline. A faster but less accurate
      model (Haiku) has already analyzed this email and was uncertain. Your job is to make the final
      decision with higher accuracy.

      CRITICAL RULES:
      1. RECALL is more important than PRECISION. If unsure, prefer "confirmed" over "excluded".
         Missing a real RFQ costs thousands of dollars; false positives waste 10 seconds.
      2. You must return either "confirmed" or "excluded". DO NOT return "uncertain".
      3. Extract structured data (customer, items, quantities, due_date) when confirmed.
      4. Consider Haiku's reasoning but DO NOT blindly follow it. Override if you see a clear signal.

      Respond ONLY with valid JSON (no markdown, no explanation).
    PROMPT

    def build_few_shots_text
      return "" unless defined?(Gmail::RfqFeedbackService)

      shots = begin
        Gmail::RfqFeedbackService.few_shot_examples(limit: FEW_SHOT_LIMIT)
      rescue StandardError => e
        Rails.logger.warn "[SonnetEscalator] few_shot 조회 실패 — 빈 배열로 폴백: #{e.class} #{e.message}"
        []
      end
      return "" if shots.empty?

      lines = shots.map do |ex|
        "- Subject: \"#{ex[:subject]}\" | From: #{ex[:from]} | Verdict: #{ex[:verdict]} | Reason: #{ex[:reason]}"
      end.join("\n")

      "PAST USER FEEDBACK EXAMPLES (learn from these):\n#{lines}"
    end

    def build_user_prompt
      haiku_confidence = haiku_value(:confidence) || "unknown"
      haiku_verdict    = haiku_value(:verdict) || "unknown"
      haiku_reason     = haiku_value(:reason) || "(no reason provided)"

      <<~PROMPT
        Analyze this email and return final RFQ verdict.

        HAIKU'S PRIOR ANALYSIS:
        - verdict: #{haiku_verdict}
        - confidence: #{haiku_confidence}
        - reason: #{haiku_reason}
        (Haiku was uncertain, that's why you are being called.)

        EMAIL:
        Subject: #{@email[:subject]}
        From: #{@email[:from]}
        Body:
        #{@email[:body].to_s.first(MAX_BODY_CHARS)}

        Return ONLY this JSON structure:
        {
          "final_verdict": "confirmed" or "excluded",
          "is_rfq": true or false,
          "sonnet_confidence": "high" or "medium",
          "override_reason": "why you agreed with Haiku or why you overrode (max 200 chars, Korean OK)",
          "extracted": {
            "customer_name": "...",
            "due_date": "YYYY-MM-DD or null",
            "items": ["..."],
            "quantities": ["..."],
            "project_name": "...",
            "currency": "USD|KRW|AED or null",
            "estimated_value": number or null,
            "urgency": "urgent|high|normal|low"
          }
        }
      PROMPT
    end

    def parse_response(response)
      first = response.content&.first
      text = if first.respond_to?(:text)
               first.text.to_s
      elsif first.is_a?(Hash)
               first[:text].to_s
      else
               ""
      end

      clean = text.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
      JSON.parse(clean)
    rescue JSON::ParserError => e
      Rails.logger.warn "[SonnetEscalator] JSON parse error: #{e.message}"
      nil
    end

    def build_result(parsed, latency:, response:)
      verdict_str = parsed["final_verdict"].to_s
      verdict_sym = case verdict_str
      when "confirmed" then :confirmed
      when "excluded"  then :excluded
      else :confirmed  # Recall 우선: 애매하면 confirmed
      end

      confidence = parsed["sonnet_confidence"].to_s.presence || "medium"

      Gmail::ClassificationResult.new(
        verdict:            verdict_sym,
        is_rfq:             parsed["is_rfq"] == true,
        confidence:         confidence,
        stage_reached:      3,
        classifier_version: "v2",
        reason:             parsed["override_reason"].to_s.first(500),
        extracted:          parsed["extracted"] || {},
        cost_usd:           compute_cost(response),
        latency_ms:         latency,
        cache_hit:          detect_cache_hit(response),
        model:              "sonnet-4.5"
      )
    end

    # Fallback: Sonnet 실패 시 Haiku 결과를 Stage 3 ClassificationResult로 변환
    # Haiku 결과도 없으면 confirmed (Recall 우선)
    def fallback_to_haiku(reason:)
      if @haiku.nil?
        return safe_confirmed_fallback(reason: "no_haiku_no_sonnet")
      end

      Gmail::ClassificationResult.new(
        verdict:            haiku_value(:verdict)&.to_sym || :confirmed,
        is_rfq:             haiku_value(:is_rfq),
        confidence:         haiku_value(:confidence) || "low",
        stage_reached:      3,  # Stage 3에서 fallback 발생
        classifier_version: "v2",
        reason:             "stage3_fallback_to_stage2: #{reason}",
        extracted:          haiku_value(:extracted) || {},
        cost_usd:           haiku_value(:cost_usd).to_f,
        latency_ms:         haiku_value(:latency_ms).to_i,
        cache_hit:          false,
        model:              "haiku-4.5-fallback"
      )
    end

    def safe_confirmed_fallback(reason:)
      Gmail::ClassificationResult.new(
        verdict:            :confirmed,  # Recall 우선
        is_rfq:             true,
        confidence:         "none",
        stage_reached:      3,
        classifier_version: "v2",
        reason:             "stage3_total_failure: #{reason}",
        extracted:          {},
        cost_usd:           0.0,
        latency_ms:         0,
        cache_hit:          false,
        model:              "rule-only-fallback"
      )
    end

    def haiku_value(key)
      return nil if @haiku.nil?

      if @haiku.respond_to?(key)
        @haiku.send(key)
      elsif @haiku.is_a?(Hash)
        @haiku[key] || @haiku[key.to_s]
      end
    end

    def compute_cost(response)
      usage = extract_usage(response)
      return 0.0 if usage.nil?

      input_cached  = usage[:cache_read_input_tokens].to_i
      input_fresh   = usage[:input_tokens].to_i
      output        = usage[:output_tokens].to_i

      # cached input은 10% 가격 (90% 할인)
      input_cost  = (input_fresh * SONNET_INPUT_PER_1M + input_cached * SONNET_INPUT_PER_1M * 0.1) / 1_000_000.0
      output_cost = output * SONNET_OUTPUT_PER_1M / 1_000_000.0
      (input_cost + output_cost).round(6)
    end

    def detect_cache_hit(response)
      usage = extract_usage(response)
      return false if usage.nil?

      usage[:cache_read_input_tokens].to_i > 0
    end

    def extract_usage(response)
      if response.respond_to?(:usage) && response.usage
        u = response.usage
        {
          input_tokens:            u.respond_to?(:input_tokens) ? u.input_tokens : u[:input_tokens],
          output_tokens:           u.respond_to?(:output_tokens) ? u.output_tokens : u[:output_tokens],
          cache_read_input_tokens: (u.respond_to?(:cache_read_input_tokens) ? u.cache_read_input_tokens : u[:cache_read_input_tokens]).to_i
        }
      elsif response.is_a?(Hash) && response[:usage]
        u = response[:usage]
        { input_tokens: u[:input_tokens], output_tokens: u[:output_tokens],
          cache_read_input_tokens: u[:cache_read_input_tokens].to_i }
      end
    rescue StandardError
      nil
    end
  end
end
