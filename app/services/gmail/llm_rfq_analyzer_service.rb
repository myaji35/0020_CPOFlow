# frozen_string_literal: true

module Gmail
  # Claude API를 활용한 지능형 RFQ 이메일 분석 서비스
  #
  # Usage:
  #   result = Gmail::LlmRfqAnalyzerService.new(parsed_email).analyze
  #   result[:is_rfq]        # => true/false
  #   result[:confidence]    # => "high" | "medium" | "low" | "none"
  #   result[:score]         # => 0-100
  #   result[:extracted]     # => { customer_name:, due_date:, items:, ... }
  class LlmRfqAnalyzerService
    MAX_BODY_CHARS = 4000  # 토큰 절약을 위해 본문 첫 4000자만 전송

    def initialize(parsed_email)
      @email = parsed_email
    end

    def analyze
      return fallback_result unless api_key_configured?

      response = call_claude_api
      parse_response(response)
    rescue => e
      Rails.logger.error "[LlmRfqAnalyzer] API error: #{e.class} — #{e.message}"
      fallback_result
    end

    private

    def api_key_configured?
      ClaudeTokenResolver.configured?
    end

    def call_claude_api
      client = ClaudeTokenResolver.create_client
      return nil unless client

      # ISS-279: 429 / 5xx / 일시적 네트워크 에러에 대해 exponential backoff + jitter 재시도 (최대 3회)
      with_retries(max: 3, base: 1.0) do
        client.messages.create(
          model: ENV.fetch("RFQ_LLM_MODEL", "claude-haiku-4-5-20251001"),
          max_tokens: 1024,
          messages: [
            {
              role: "user",
              content: build_prompt
            }
          ]
        )
      end
    end

    # ISS-279: 429/5xx/Timeout 재시도 헬퍼 — SDK/Faraday/Net::HTTP 모두 커버
    def with_retries(max: 3, base: 1.0)
      attempt = 0
      begin
        attempt += 1
        yield
      rescue => e
        if retryable_api_error?(e) && attempt < max
          sleep_for = base * (2 ** (attempt - 1)) + rand(0.0..0.5)
          Rails.logger.warn "[LlmRfqAnalyzer] retry #{attempt}/#{max} after #{sleep_for.round(2)}s — #{e.class}: #{e.message.to_s.truncate(120)}"
          sleep(sleep_for)
          retry
        else
          raise
        end
      end
    end

    def retryable_api_error?(e)
      msg = e.message.to_s
      # Anthropic SDK 에러 클래스 존재 시 매칭 (명시 require 안 하고 defined?로 가드)
      return true if defined?(::Anthropic::Errors::RateLimitError) && e.is_a?(::Anthropic::Errors::RateLimitError)
      return true if defined?(::Anthropic::Errors::APIError)       && e.is_a?(::Anthropic::Errors::APIError) && msg.match?(/\b5\d\d\b/)
      return true if defined?(::Faraday::TimeoutError)             && e.is_a?(::Faraday::TimeoutError)
      return true if defined?(::Faraday::ConnectionFailed)         && e.is_a?(::Faraday::ConnectionFailed)
      return true if defined?(::Faraday::ServerError)              && e.is_a?(::Faraday::ServerError)
      return true if defined?(::Net::ReadTimeout)                  && e.is_a?(::Net::ReadTimeout)
      return true if defined?(::Net::OpenTimeout)                  && e.is_a?(::Net::OpenTimeout)
      # 문자열 매칭 fallback
      msg.match?(/\b(429|502|503|504)\b|rate.?limit|too many requests|timeout/i)
    end

    def build_prompt
      few_shots = Gmail::RfqFeedbackService.few_shot_examples(limit: 5)
      domain    = @email[:from].to_s.match(/@([^>]+)>?/)&.[](1)&.strip&.downcase
      history   = Gmail::RfqFeedbackService.domain_history(domain)

      few_shot_section = if few_shots.any?
        lines = few_shots.map do |ex|
          "  - Subject: \"#{ex[:subject]}\" | From: #{ex[:from]} | Verdict: #{ex[:verdict]} | Reason: #{ex[:reason]}"
        end.join("\n")
        "\nPAST USER FEEDBACK (few-shot examples — learn from these):\n#{lines}\n"
      else
        ""
      end

      history_section = if history[:confirmed] > 0 || history[:rejected] > 0
        "\nSENDER DOMAIN HISTORY for \"#{domain}\": #{history[:confirmed]} confirmed RFQs, #{history[:rejected]} rejected. " +
        (history[:confirmed] > 0 ? "This domain has sent valid RFQs before — lean toward confirmed." : "")
      else
        ""
      end

      <<~PROMPT
        You are an expert procurement specialist at AtoZ2010, a company that supplies construction materials (Sika waterproofing, concrete admixtures, adhesives, sealants, grouts) to large infrastructure projects in the Middle East and South Korea.

        Analyze the following email and determine if it is an RFQ (Request for Quotation) or procurement inquiry.
        #{few_shot_section}#{history_section}

        EMAIL:
        Subject: #{@email[:subject]}
        From: #{@email[:from]}
        Body:
        #{@email[:body].to_s.first(MAX_BODY_CHARS)}

        Respond ONLY with valid JSON (no markdown, no explanation):
        {
          "is_rfq": true/false,
          "confidence": "high|medium|low|none",
          "score": 0-100,
          "reason": "brief explanation in Korean (max 100 chars)",
          "extracted": {
            "customer_name": "company name or null",
            "customer_email": "email address or null",
            "due_date": "YYYY-MM-DD or null",
            "items": ["item1", "item2"] or [],
            "quantities": ["qty1 unit1", "qty2 unit2"] or [],
            "project_name": "project name or null",
            "delivery_location": "location or null",
            "currency": "USD|KRW|AED or null",
            "estimated_value": number or null,
            "language": "en|ko|ar",
            "urgency": "urgent|high|normal|low"
          }
        }
      PROMPT
    end

    def parse_response(response)
      # SDK 1.x: response.content는 배열, 각 요소는 해시 또는 객체
      first = response.content&.first
      content = if first.respond_to?(:text)
        first.text.to_s
      elsif first.is_a?(Hash)
        first[:text].to_s
      else
        ""
      end

      # 마크다운 코드블록 제거 (```json ... ``` 패턴)
      clean_content = content.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
      parsed = JSON.parse(clean_content)

      due_date = begin
        Date.parse(parsed.dig("extracted", "due_date").to_s) if parsed.dig("extracted", "due_date")
      rescue
        nil
      end

      {
        is_rfq:            parsed["is_rfq"] == true,
        confidence:        parsed["confidence"] || "none",
        score:             parsed["score"].to_i,
        reason:            parsed["reason"],
        customer_name:     parsed.dig("extracted", "customer_name"),
        due_date:          due_date,
        items:             parsed.dig("extracted", "items") || [],
        quantities:        parsed.dig("extracted", "quantities") || [],
        project_name:      parsed.dig("extracted", "project_name"),
        delivery_location: parsed.dig("extracted", "delivery_location"),
        currency:          parsed.dig("extracted", "currency"),
        estimated_value:   parsed.dig("extracted", "estimated_value"),
        urgency:           parsed.dig("extracted", "urgency") || "normal",
        raw:               parsed
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "[LlmRfqAnalyzer] JSON parse error: #{e.message}"
      fallback_result
    end

    # LLM 실패 시 nil 반환 → RfqDetectorService에서 키워드만으로 판정
    def fallback_result
      {
        is_rfq: nil, confidence: "none", score: nil,
        reason: "LLM 분석 불가 (API 키 미설정 또는 크레딧 부족)",
        llm_unavailable: true,
        customer_name: nil, due_date: nil, items: [], quantities: [],
        project_name: nil, delivery_location: nil,
        currency: nil, estimated_value: nil,
        urgency: "normal", raw: {}
      }
    end
  end
end
