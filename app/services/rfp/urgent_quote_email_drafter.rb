# ISS-328: 긴급 견적 의뢰 메일 초안 생성기
# Claude Haiku 사용 — 한/영 양쪽 초안 반환
module Rfp
  class UrgentQuoteEmailDrafter
    MODEL = "claude-haiku-4-5"
    MAX_TOKENS = 1500
    API_URL = "https://api.anthropic.com/v1/messages"
    API_VERSION = "2023-06-01"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a professional procurement email writer. Generate urgent quotation request emails in both Korean and English.

      The email must be:
      - Polite but firm about urgency
      - Clear about the 24-hour reply deadline
      - Professional and concise

      Return ONLY valid JSON:
      {
        "subject_ko": "제목 (한국어)",
        "subject_en": "Subject (English)",
        "body_ko": "본문 (한국어, 3-4단락)",
        "body_en": "Body (English, 3-4 paragraphs)"
      }
    PROMPT

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      api_key = Rails.application.credentials.dig(:anthropic, :api_key)
      return error_draft("API key not configured") if api_key.blank?

      payload = build_payload
      response = make_request(api_key, payload)
      return error_draft("API request failed") unless response

      parse_response(response)
    rescue => e
      Rails.logger.error("[Rfp::UrgentQuoteEmailDrafter] order=#{@order.id} #{e.class}: #{e.message}")
      error_draft(e.message)
    end

    private

    def build_payload
      {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: build_user_message
          }
        ]
      }
    end

    def build_user_message
      parts = []
      parts << "긴급 견적 의뢰 이메일을 한국어와 영어로 작성해주세요."
      parts << ""
      parts << "발주 정보:"
      parts << "- 건명: #{@order.title}"
      parts << "- 품목: #{@order.item_name.presence || '첨부파일 참조'}"
      parts << "- 수량: #{@order.quantity.present? ? "#{@order.quantity} #{@order.respond_to?(:quantity_unit) ? @order.quantity_unit.to_s : ''}" : '협의'}"
      parts << "- 마감일: #{@order.due_date&.strftime('%Y-%m-%d') || '즉시'}"
      parts << "- 거래처: #{@order.supplier&.name || '수신자 귀하'}"
      parts << "- 발주처: #{@order.client&.name || '당사'}"
      parts << ""
      parts << "요청사항: 24시간 이내 견적 회신 필요. 긴급 상황임을 명시."
      parts.join("\n")
    end

    def make_request(api_key, payload)
      require "net/http"
      require "uri"

      uri = URI.parse(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      http.open_timeout = 15

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"] = "application/json"
      req["x-api-key"] = api_key
      req["anthropic-version"] = API_VERSION
      req.body = payload.to_json

      resp = http.request(req)
      unless resp.code.to_i == 200
        Rails.logger.error("[Rfp::UrgentQuoteEmailDrafter] HTTP #{resp.code}")
        return nil
      end

      JSON.parse(resp.body)
    rescue => e
      Rails.logger.error("[Rfp::UrgentQuoteEmailDrafter] HTTP fail: #{e.message}")
      nil
    end

    def parse_response(api_response)
      content = api_response.dig("content", 0, "text").to_s.strip
      json_str = content.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
      result = JSON.parse(json_str)

      {
        subject_ko: result["subject_ko"].to_s,
        subject_en: result["subject_en"].to_s,
        body_ko: result["body_ko"].to_s,
        body_en: result["body_en"].to_s,
        error: nil
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[Rfp::UrgentQuoteEmailDrafter] JSON parse fail: #{e.message}")
      error_draft("메일 초안 생성 중 파싱 오류가 발생했습니다.")
    end

    def error_draft(reason)
      {
        subject_ko: "[긴급] 견적 의뢰 — #{@order.title.to_s.first(30)}",
        subject_en: "[URGENT] Quotation Request — #{@order.title.to_s.first(30)}",
        body_ko: "안녕하세요,\n\n#{@order.title} 건에 대해 긴급 견적을 요청드립니다.\n상세 내용은 첨부파일을 참조해 주시고, 24시간 이내 회신 부탁드립니다.\n\n감사합니다.",
        body_en: "Dear Sir/Madam,\n\nWe urgently request a quotation for: #{@order.title}.\nPlease refer to the attached documents and reply within 24 hours.\n\nBest regards.",
        error: reason
      }
    end
  end
end
