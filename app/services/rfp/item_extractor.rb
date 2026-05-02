# ISS-293: RFP 품목 추출 LLM 서비스
# Claude Opus 4.7 호출 → JSON 품목 배열 반환
module Rfp
  class ItemExtractor
    MODEL = "claude-opus-4-7"
    MAX_TOKENS = 4096
    API_URL = "https://api.anthropic.com/v1/messages"
    API_VERSION = "2023-06-01"

    BASE_SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert procurement analyst. Extract all line items from the RFP/RFQ document text provided.

      Return ONLY valid JSON matching this exact schema:
      {
        "items": [
          {
            "name": "품목명 (string, required)",
            "spec": "사양 상세 (string or null)",
            "quantity": 3,
            "unit": "SET",
            "delivery_date": "YYYY-MM-DD or null",
            "material_code": "자재코드 or null",
            "manufacturer": "제조사 or null",
            "source_excerpt": "원문에서 직접 인용한 30자 이상의 문장 (REQUIRED - 할루시네이션 방지용)"
          }
        ],
        "rfp_deadline": "YYYY-MM-DD or null",
        "checklist": {%<checklist_schema>s},
        "confidence": 0.85,
        "ambiguities": ["수량 단위 모호", "납기일 미기재"]
      }

      Rules:
      1. source_excerpt is MANDATORY for each item — skip items without it
      2. source_excerpt must be verbatim text from the document (minimum 30 characters)
      3. quantity must be a number (not string)
      4. If no items found, return {"items": [], "rfp_deadline": null, "checklist": {}, "confidence": 0.0, "ambiguities": ["품목 없음"]}
      5. Return ONLY the JSON object, no markdown fences, no explanation
      6. rfp_deadline: the EARLIEST/most urgent deadline in the document — look for keywords like "Submission Deadline", "Close Date", "마감일", "제출기한", or the earliest delivery_date among all items. Return null if not found.

      ## Checklist (ISS-330)
      Extract the following standard checklist items into "checklist":
      %<checklist_hints>s
      For values not found in the document, use null. For arrays, use [] when empty.
    PROMPT

    def self.call(combined_text)
      new.call(combined_text)
    end

    def call(combined_text)
      return nil if combined_text.blank?

      api_key = Rails.application.credentials.dig(:anthropic, :api_key)
      return nil if api_key.blank?

      payload = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: build_system_prompt,
        messages: [
          {
            role: "user",
            content: "다음 RFP 문서에서 품목을 추출하세요:\n\n#{combined_text}"
          }
        ]
      }

      response = make_request(api_key, payload)
      return nil unless response

      parse_response(response)
    rescue => e
      Rails.logger.error("[Rfp::ItemExtractor] API error: #{e.class}: #{e.message}")
      nil
    end

    private

    # ISS-330: 활성 ChecklistItem들로 system prompt 동적 생성
    def build_system_prompt
      items = ChecklistItem.active.ordered.to_a
      checklist_schema = items.map { |i| "\"#{i.code}\": \"value or null\"" }.join(", ")
      checklist_hints = items.map(&:prompt_fragment).join("\n")
      format(BASE_SYSTEM_PROMPT, checklist_schema: checklist_schema, checklist_hints: checklist_hints)
    rescue => e
      Rails.logger.warn("[Rfp::ItemExtractor] checklist build failed, using base: #{e.message}")
      format(BASE_SYSTEM_PROMPT, checklist_schema: "", checklist_hints: "(no checklist configured)")
    end

    def make_request(api_key, payload)
      require "net/http"
      require "uri"
      require "json"

      uri = URI.parse(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = api_key
      request["anthropic-version"] = API_VERSION

      request.body = payload.to_json

      resp = http.request(request)

      unless resp.code.to_i == 200
        Rails.logger.error("[Rfp::ItemExtractor] HTTP #{resp.code}: #{resp.body.slice(0, 500)}")
        return nil
      end

      JSON.parse(resp.body)
    rescue => e
      Rails.logger.error("[Rfp::ItemExtractor] HTTP request failed: #{e.class}: #{e.message}")
      nil
    end

    def parse_response(api_response)
      content = api_response.dig("content", 0, "text")
      return nil if content.blank?

      # JSON 추출 (마크다운 펜스 방어)
      json_str = content.strip
      json_str = json_str.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip

      result = JSON.parse(json_str)

      # items 키 없으면 nil
      return nil unless result.is_a?(Hash) && result["items"].is_a?(Array)

      result
    rescue JSON::ParserError => e
      Rails.logger.error("[Rfp::ItemExtractor] JSON parse error: #{e.message} | content: #{content&.slice(0, 300)}")
      nil
    end
  end
end
