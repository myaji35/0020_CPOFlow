# frozen_string_literal: true

# RFQ Auto Phase 4 — 공급사 인터넷 리서치 (Anthropic Web Search Tool).
# 호출:
#   results = RfqAuto::WebSupplierFinder.new(items, max_per_item: 5).call
#   # => { suppliers: [...], cost_usd: 0.05, model: "claude-sonnet-4-6", citations: [...] }
#
# 작동:
#   - Sonnet 4.6 + web_search tool로 모델이 직접 구글링
#   - 품목 1~3개를 1회 호출로 묶어 처리 (비용 절감)
#   - JSON 응답: [{name, country, website, contact_email, phone, source_url, confidence}]
#   - 인용 URL 추적 → UI에서 출처 클릭 가능
#
# 비용:
#   Sonnet 4.6 — input $3/M, output $15/M tokens
#   web_search — Anthropic 별도 과금 ($10/1000 검색 호출, 2025-04 기준)
#   품목 3개 묶음 1회 호출 ≈ $0.05~0.10 예상
#
# 잔액 부족: AnthropicCreditError → 컨트롤러가 사용자에게 충전 요청 보고
require "net/http"
require "uri"
require "json"

module RfqAuto
  class WebSupplierFinder
    MODEL = ENV.fetch("RFQ_WEB_SEARCH_MODEL", "claude-sonnet-4-6")
    API_URL = "https://api.anthropic.com/v1/messages"
    API_VERSION = "2023-06-01"
    MAX_TOKENS = 4096
    INPUT_PER_MTOK   = 3.00
    OUTPUT_PER_MTOK  = 15.00

    class AnthropicCreditError < StandardError; end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a procurement researcher. Use web search to find verified suppliers.

      For each item below, search the web and return suppliers focusing on:
      - South Korea and UAE first (primary markets)
      - Manufacturer/distributor official websites preferred over directories
      - Verify contact info (email, phone) from the actual company page

      Return ONLY a JSON object (no markdown, no commentary):
      {
        "suppliers": [
          {
            "item_keyword": "product name searched",
            "name": "Company Name",
            "country": "KR / AE / US / DE / CN / etc",
            "website": "https://...",
            "contact_email": "sales@...",
            "phone": "+82-2-...",
            "source_url": "URL where you found this info",
            "confidence": 75
          }
        ]
      }

      Rules:
      - 3-5 suppliers per item maximum
      - confidence 0-100 (90+ = official site verified, 70+ = directory listing, 50+ = mentioned in catalog)
      - skip if no real supplier found (don't hallucinate)
      - source_url is REQUIRED for verification
    PROMPT

    def initialize(items, max_per_item: 5)
      @items = items.is_a?(Array) ? items.first(3) : []  # 비용 통제 — 최대 3품목/호출
      @max_per_item = max_per_item
    end

    def call
      return empty_result(reason: "no items") if @items.empty?

      keywords = @items.map { |i| (i.is_a?(Hash) ? (i[:name] || i["name"]) : nil).to_s.strip }.reject(&:blank?)
      return empty_result(reason: "no keywords") if keywords.empty?

      token_info = ClaudeTokenResolver.resolve
      return empty_result(reason: "no api key") if token_info.nil?

      user_msg = "Find suppliers for these procurement items (search the web):\n\n" +
                 keywords.map.with_index(1) { |k, i| "#{i}. #{k}" }.join("\n")

      response = post_messages(token_info, user_msg)
      return empty_result(reason: "api failed") unless response

      input_tokens, output_tokens, suppliers, citations = parse_response(response)
      cost = (input_tokens.to_f * INPUT_PER_MTOK + output_tokens.to_f * OUTPUT_PER_MTOK) / 1_000_000

      enriched = suppliers.map do |s|
        {
          source:        "web_search",
          confidence:    (s["confidence"] || 60).to_i,
          name:          s["name"].to_s,
          email:         s["contact_email"],
          phone:         s["phone"],
          website:       s["website"],
          country:       s["country"],
          item_keyword:  s["item_keyword"],
          source_url:    s["source_url"]
        }
      end

      {
        suppliers:     enriched,
        cost_usd:      cost.round(4),
        model:         MODEL,
        input_tokens:  input_tokens,
        output_tokens: output_tokens,
        citations:     citations
      }
    end

    private

    def empty_result(reason:)
      { suppliers: [], cost_usd: 0.0, model: MODEL, input_tokens: 0, output_tokens: 0, citations: [], reason: reason }
    end

    def post_messages(token_info, user_msg)
      uri = URI.parse(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["anthropic-version"] = API_VERSION
      if token_info[:auth] == :bearer
        request["Authorization"] = "Bearer #{token_info[:key]}"
      else
        request["x-api-key"] = token_info[:key]
      end

      request.body = {
        model:      MODEL,
        max_tokens: MAX_TOKENS,
        system:     SYSTEM_PROMPT,
        # Anthropic web_search tool — 모델이 직접 google fetch + 인용
        tools:      [ { type: "web_search_20250305", name: "web_search", max_uses: 5 } ],
        messages:   [ { role: "user", content: user_msg } ]
      }.to_json

      resp = http.request(request)
      unless resp.code.to_i == 200
        body = resp.body.to_s.slice(0, 500)
        Rails.logger.error("[WebSupplierFinder] HTTP #{resp.code}: #{body}")
        if body.match?(/credit|balance|insufficient|quota/i)
          raise AnthropicCreditError, "Anthropic 잔액 부족 — 충전 후 재시도 (#{body.slice(0, 160)})"
        end
        return nil
      end
      JSON.parse(resp.body)
    rescue StandardError => e
      Rails.logger.error("[WebSupplierFinder] HTTP error: #{e.class}: #{e.message}")
      raise if e.message.to_s.include?("잔액 부족")
      nil
    end

    def parse_response(api_response)
      usage = api_response["usage"] || {}
      input_tokens  = usage["input_tokens"].to_i
      output_tokens = usage["output_tokens"].to_i

      # content는 array — text/tool_use/tool_result 블록 혼합
      content_blocks = api_response["content"] || []
      text_blocks = content_blocks.select { |b| b["type"] == "text" }
      json_text = text_blocks.map { |b| b["text"].to_s }.join("\n")

      # citation 수집 (web_search tool이 반환)
      citations = []
      content_blocks.each do |b|
        next unless b["citations"].is_a?(Array)
        b["citations"].each do |c|
          citations << { url: c["url"], title: c["title"], cited_text: c["cited_text"].to_s.truncate(120) }
        end
      end

      json_str = json_text.strip.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
      parsed = nil
      begin
        parsed = JSON.parse(json_str)
      rescue JSON::ParserError
        # 본문 어딘가 첫 { … } 블록 추출 시도
        m = json_str.match(/\{.*\}/m)
        parsed = (JSON.parse(m[0]) rescue {}) if m
      end

      suppliers = (parsed.is_a?(Hash) ? parsed["suppliers"] : nil) || []
      [ input_tokens, output_tokens, suppliers, citations ]
    end
  end
end
