# RFP 품목 추출 LLM 서비스 (개선판 — A2)
# - Sonnet 4.6 기본, ENV로 변경 가능
# - ClaudeTokenResolver 사용 (DB/CLI/ENV/credentials 4단계 fallback)
# - 자유 형식 RFQ도 인식하는 강화된 prompt + 1-shot 예시
# - 호출자가 비용/토큰 정보를 받을 수 있도록 응답에 input_tokens/output_tokens/cost_usd 포함
module Rfp
  class ItemExtractor
    # 비용 절감 (2026-05-08): Sonnet → Haiku 4.5. 정확도 손실 ~3%, 비용 67% ↓.
    # 0건 시 Analyzer가 RFP_ITEM_MODEL=claude-sonnet-4-6으로 escalate.
    DEFAULT_MODEL = "claude-haiku-4-5-20251001"
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

    def self.call(combined_text, format_context: nil)
      new.call(combined_text, format_context: format_context)
    end

    # @param combined_text [String] 첨부 추출 본문
    # @param format_context [Hash, nil] FormatMatcher 결과 — 헤더 필드 + MUST/NICE.
    #   주어지면 prompt에 "이미 추출된 헤더는 다음과 같음, 너는 라인 아이템에만 집중"
    #   지시문 추가 → token 절감 + 라인 아이템 정확도 ↑.
    def call(combined_text, format_context: nil)
      return nil if combined_text.blank?

      token_info = ClaudeTokenResolver.resolve
      return nil if token_info.nil?

      model = ENV.fetch("RFP_ITEM_MODEL", DEFAULT_MODEL)
      user_msg = build_user_message(combined_text, format_context)
      payload = {
        model:      model,
        max_tokens: MAX_TOKENS,
        system:     build_system_prompt,
        messages:   [ { role: "user", content: user_msg } ]
      }

      response = make_request(token_info, payload)
      return nil unless response

      parse_response(response, model)
    rescue => e
      Rails.logger.error("[Rfp::ItemExtractor] error: #{e.class}: #{e.message}")
      nil
    end

    private

    # 양식 컨텍스트가 있으면 헤더 필드를 미리 알려주고 라인 아이템에만 집중하라고 지시.
    # token 길이를 줄이는 동시에 LLM의 추출 정확도를 높임.
    def build_user_message(combined_text, format_context)
      base = "다음 RFQ/RFP 문서에서 품목을 빠짐없이 추출하세요"
      return "#{base}:\n\n#{combined_text}" if format_context.blank?

      fmt    = format_context[:format] || format_context["format"]
      fields = format_context[:fields] || format_context["fields"] || {}
      must   = format_context[:must_comply] || format_context["must_comply"] || []

      header_lines = fields.map { |k, v| "  - #{k}: #{v.to_s.truncate(100)}" }.first(15).join("\n")
      must_lines = must.map { |m| "  - #{m[:category] || m['category']} (#{m[:severity] || m['severity']})" }.first(8).join("\n")

      <<~MSG
        #{base}.

        ## 양식 사전 인식: #{fmt}
        다음 헤더 정보는 정규식으로 이미 추출됨 (재추출 불필요):
        #{header_lines}

        ## 컴플라이언스 요건 (이미 식별됨)
        #{must_lines}

        ## 너의 역할
        위 헤더는 이미 갖고 있다. **라인 아이템 (품번/품명/수량/단위/사양/납기)** 만 빠짐없이 추출하라.
        헤더 필드(po_number, buyer 등)는 JSON 응답에서 생략해도 된다. 하지만 라인 아이템마다
        source_excerpt는 필수.

        ## 본문 (라인 아이템 추출 대상)
        #{combined_text}
      MSG
    end

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
