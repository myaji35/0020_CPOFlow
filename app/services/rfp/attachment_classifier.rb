# ISS-307: 첨부파일 유형 자동 분류 서비스
# 입력: ActiveStorage::Attachment
# 출력: { type: String, confidence: Float, evidence: String, source: String }
#
# 단계:
#   1. 파일명 휴리스틱 우선 (패턴 매칭 → 즉시 반환)
#   2. 휴리스틱 불확실 시 Rfp::AttachmentExtractor로 텍스트 추출
#   3. Claude Haiku로 분류 (저비용)
#   4. 결과 hash 반환
require "net/http"
require "json"
require "uri"

module Rfp
  class AttachmentClassifier
    TYPES = %w[rfq quotation po invoice packing_list grn delivery_note other].freeze

    # lookbehind/lookahead로 언더스코어/숫자 구분자도 인식 (e.g. PO_FINAL, quote_v2)
    FILENAME_HEURISTICS = {
      /(?<![a-z])(rfq|rfp|enquiry|inquiry|enq)(?![a-z])/i  => "rfq",
      /(?<![a-z])(quo|quote|quotation)(?![a-z])/i           => "quotation",
      /(?<![a-z])(po|purchase[\s_-]?order)(?![a-z])/i       => "po",
      /(?<![a-z])(inv|invoice|bill)(?![a-z])/i              => "invoice",
      /(?<![a-z])(pkg|pack|packing)(?![a-z])/i              => "packing_list",
      /(?<![a-z])(grn|goods[\s_-]?received)(?![a-z])/i      => "grn",
      /(?<![a-z])(delivery[\s_-]?note|deli?note)(?![a-z])/i => "delivery_note"
    }.freeze

    HAIKU_MODEL = ENV.fetch("RFQ_LLM_MODEL", "claude-haiku-4-5-20251001")

    def self.call(attachment)
      new(attachment).call
    end

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      # ISS-333: 노이즈 첨부 (ariba_login_capture 등) 즉시 other로 분류
      relevance = Rfp::AttachmentRelevanceFilter.call(@attachment)
      unless relevance[:relevant]
        return { type: "other", confidence: 0.95, evidence: "noise filter: #{relevance[:reason]}", source: "noise_filter" }
      end

      filename = @attachment.blob.filename.to_s
      heuristic = filename_heuristic(filename)
      return { type: heuristic, confidence: 0.85, evidence: "filename: #{filename}", source: "heuristic" } if heuristic

      # 텍스트 추출 후 LLM 분류
      extracted = Rfp::AttachmentExtractor.call(@attachment)
      text = extracted[:text]
      return { type: "other", confidence: 0.0, evidence: "no text extractable", source: "fallback" } if text.blank?

      llm_classify(text.first(2000), filename)
    rescue => e
      Rails.logger.error("[Rfp::AttachmentClassifier] #{e.class}: #{e.message}")
      { type: "other", confidence: 0.0, evidence: "error: #{e.message}", source: "error" }
    end

    private

    def filename_heuristic(filename)
      FILENAME_HEURISTICS.each do |pattern, type|
        return type if filename =~ pattern
      end
      nil
    end

    def llm_classify(text_excerpt, filename)
      api_key = Rails.application.credentials.dig(:anthropic, :api_key)
      return { type: "other", confidence: 0.0, evidence: "no api key configured", source: "no_key" } if api_key.blank?

      uri = URI("https://api.anthropic.com/v1/messages")
      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["content-type"] = "application/json"
      req.body = JSON.generate(
        model: HAIKU_MODEL,
        max_tokens: 200,
        messages: [
          {
            role: "user",
            content: <<~PROMPT
              다음 첨부파일이 어떤 유형인지 분류하세요.
              유형: #{TYPES.join(", ")}

              파일명: #{filename}
              본문 발췌:
              ---
              #{text_excerpt}
              ---

              JSON으로만 응답 (설명 없이):
              {"type": "rfq|quotation|po|invoice|packing_list|grn|delivery_note|other", "confidence": 0.0~1.0, "evidence": "근거 한 줄"}
            PROMPT
          }
        ]
      )

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 5) do |h|
        h.request(req)
      end

      unless res.code == "200"
        Rails.logger.warn("[Rfp::AttachmentClassifier] HTTP #{res.code}: #{res.body.first(200)}")
        return { type: "other", confidence: 0.0, evidence: "http #{res.code}", source: "http_error" }
      end

      body = JSON.parse(res.body)
      content = body.dig("content", 0, "text").to_s
      json_str = content[/\{.*\}/m]
      unless json_str
        Rails.logger.warn("[Rfp::AttachmentClassifier] No JSON in response: #{content.first(200)}")
        return { type: "other", confidence: 0.0, evidence: "no json in response", source: "parse_error" }
      end

      parsed = JSON.parse(json_str)
      type = parsed["type"].to_s
      type = "other" unless TYPES.include?(type)
      {
        type: type,
        confidence: parsed["confidence"].to_f.clamp(0.0, 1.0),
        evidence: parsed["evidence"].to_s.first(200),
        source: "llm"
      }
    rescue JSON::ParserError => e
      Rails.logger.warn("[Rfp::AttachmentClassifier] JSON parse error: #{e.message}")
      { type: "other", confidence: 0.0, evidence: "json error: #{e.message}", source: "parse_error" }
    end
  end
end
