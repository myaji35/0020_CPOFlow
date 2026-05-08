# RFP 품목 추출 LLM 서비스 (개선판 — A2)
# - Sonnet 4.6 기본, ENV로 변경 가능
# - ClaudeTokenResolver 사용 (DB/CLI/ENV/credentials 4단계 fallback)
# - 자유 형식 RFQ도 인식하는 강화된 prompt + 1-shot 예시
# - 호출자가 비용/토큰 정보를 받을 수 있도록 응답에 input_tokens/output_tokens/cost_usd 포함
module Rfp
  class ItemExtractor
    DEFAULT_MODEL = "claude-sonnet-4-6"
    MODEL_PRICING = {
      "claude-haiku-4-5-20251001" => { input: 1.0,  output: 5.0  },
      "claude-sonnet-4-6"          => { input: 3.0,  output: 15.0 },
      "claude-opus-4-7"            => { input: 15.0, output: 75.0 }
    }.freeze
    MAX_TOKENS  = 4096
    API_URL     = "https://api.anthropic.com/v1/messages"
    API_VERSION = "2023-06-01"

    BASE_SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert procurement analyst extracting line items from RFQ/RFP documents.

      INPUT FORMATS YOU MUST HANDLE
      - Structured tables (Excel-like with header row)
      - Bullet/numbered lists ("1. Pressure Gauge 0-10 bar, qty 5 EA")
      - Free-form sentences ("We need 3 sets of XYZ valves with KS certification by 2026-06-15")
      - Email body + attachment combined text
      - Korean / English / Arabic mixed content

      EXTRACT EVEN IF
      - Quantity is missing (return null) — still create the item
      - Specs are scattered across paragraphs
      - The document is a registration/insurance/policy form (in that case return items: [] but DO check checklist fields)
      - Items mentioned only in passing ("require XYZ", "looking for ABC")

      Return ONLY valid JSON in this schema (no markdown fences, no commentary):
      {
        "items": [
          {
            "name": "품목명 (REQUIRED, English preferred)",
            "model": "model number or null",
            "spec": "specs (material/pressure/voltage/dimension)",
            "quantity": 3,
            "unit": "SET / EA / PCS / M / KG",
            "certification": "KS/CE/API/ATEX/ISO if mentioned, else null",
            "delivery_date": "YYYY-MM-DD or null",
            "manufacturer": "OEM brand or null",
            "source_excerpt": "verbatim 30+ char quote from document (REQUIRED — 할루시네이션 차단)"
          }
        ],
        "rfp_deadline": "YYYY-MM-DD or null",
        "checklist": {%<checklist_schema>s},
        "confidence": 0.85,
        "ambiguities": ["수량 단위 모호", "납기일 미기재"]
      }

      RULES
      1. source_excerpt is MANDATORY — if you can't find verbatim quote, skip the item.
      2. quantity must be a JSON number (not string). If unknown, use null.
      3. Be GENEROUS — extract every plausible product mentioned. Better to over-extract than miss.
      4. Return {"items": [], ...} ONLY if the document has truly NO mention of any procurable item
         (e.g. it's a registration form, policy doc, or marketing material).
      5. Return ONLY the JSON object, no fences, no explanation.
      6. rfp_deadline: earliest deadline ("Submission Deadline", "Close Date", "마감일", "제출기한") or earliest delivery_date.

      ## Checklist (ISS-330)
      Extract these standard checklist items into "checklist":
      %<checklist_hints>s
      Use null for not-found values, [] for empty arrays.

      ## Example (1-shot)
      Input: "We urgently need 5 sets of pressure gauge model PG-100, range 0-10 bar with KS cert by June 30."
      Output: {"items":[{"name":"Pressure Gauge","model":"PG-100","spec":"range 0-10 bar","quantity":5,"unit":"SET","certification":"KS","delivery_date":"2026-06-30","manufacturer":null,"source_excerpt":"We urgently need 5 sets of pressure gauge model PG-100, range 0-10 bar with KS cert by June 30."}],"rfp_deadline":"2026-06-30","checklist":{},"confidence":0.92,"ambiguities":[]}
    PROMPT

    def self.call(combined_text)
      new.call(combined_text)
    end

    def call(combined_text)
      return nil if combined_text.blank?

      token_info = ClaudeTokenResolver.resolve
      return nil if token_info.nil?

      model = ENV.fetch("RFP_ITEM_MODEL", DEFAULT_MODEL)
      payload = {
        model:      model,
        max_tokens: MAX_TOKENS,
        system:     build_system_prompt,
        messages:   [
          { role: "user", content: "다음 RFQ/RFP 문서에서 품목을 빠짐없이 추출하세요:\n\n#{combined_text}" }
        ]
      }

      response = make_request(token_info, payload)
      return nil unless response

      parse_response(response, model)
    rescue => e
      Rails.logger.error("[Rfp::ItemExtractor] error: #{e.class}: #{e.message}")
      nil
    end

    private

    def build_system_prompt
      items = ChecklistItem.active.ordered.to_a
      checklist_schema = items.map { |i| "\"#{i.code}\": \"value or null\"" }.join(", ")
      checklist_hints = items.map(&:prompt_fragment).join("\n")
      format(BASE_SYSTEM_PROMPT, checklist_schema: checklist_schema, checklist_hints: checklist_hints)
    rescue => e
      Rails.logger.warn("[Rfp::ItemExtractor] checklist build failed: #{e.message}")
      format(BASE_SYSTEM_PROMPT, checklist_schema: "", checklist_hints: "(no checklist configured)")
    end

    def make_request(token_info, payload)
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
      request["anthropic-version"] = API_VERSION
      if token_info[:auth] == :bearer
        request["Authorization"] = "Bearer #{token_info[:key]}"
      else
        request["x-api-key"] = token_info[:key]
      end
      request.body = payload.to_json

      resp = http.request(request)

      unless resp.code.to_i == 200
        body = resp.body.to_s.slice(0, 500)
        Rails.logger.error("[Rfp::ItemExtractor] HTTP #{resp.code}: #{body}")
        # 잔액 부족 감지 → 메모리 정책에 따라 명시적 표면화
        if body.match?(/credit|balance|insufficient|quota/i)
          raise "❗ Anthropic API 잔액 부족 — 충전 후 재시도 (#{body.slice(0, 160)})"
        end
        return nil
      end

      JSON.parse(resp.body)
    rescue => e
      Rails.logger.error("[Rfp::ItemExtractor] HTTP request failed: #{e.class}: #{e.message}")
      raise if e.message.include?("잔액 부족")
      nil
    end

    def parse_response(api_response, model)
      content = api_response.dig("content", 0, "text")
      return nil if content.blank?

      json_str = content.strip.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
      result = JSON.parse(json_str)
      return nil unless result.is_a?(Hash) && result["items"].is_a?(Array)

      # 비용/토큰 메타 첨부 — 호출자가 누적할 수 있도록
      usage = api_response["usage"] || {}
      input_tokens  = usage["input_tokens"].to_i
      output_tokens = usage["output_tokens"].to_i
      pricing = MODEL_PRICING[model] || MODEL_PRICING[DEFAULT_MODEL]
      cost = (input_tokens * pricing[:input] + output_tokens * pricing[:output]) / 1_000_000.0

      result.merge(
        "_model"         => model,
        "_input_tokens"  => input_tokens,
        "_output_tokens" => output_tokens,
        "_cost_usd"      => cost.round(4)
      )
    rescue JSON::ParserError => e
      Rails.logger.error("[Rfp::ItemExtractor] JSON parse error: #{e.message} | content: #{content&.slice(0, 300)}")
      nil
    end
  end
end
