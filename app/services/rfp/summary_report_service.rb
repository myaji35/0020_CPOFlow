module Rfp
  class SummaryReportService
    MODEL = "claude-haiku-4-5-20251001"
    API_URL = "https://api.anthropic.com/v1/messages"
    API_VERSION = "2023-06-01"
    MAX_TOKENS = 1200
    FAILURE_MESSAGE = "(영문 요약 생성 실패 — 재시도 필요)"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      Write a concise English summary for a procurement officer.
      Return ONLY plain English text (no JSON, no markdown fences), in 3 to 5 sentences.
      Include what is being requested, quantities, deadline, key certifications or compliance requirements, and the action needed.
    PROMPT

    def self.call(order, extraction_result)
      new(order, extraction_result).call
    end

    def initialize(order, extraction_result)
      @order = order
      @extraction_result = extraction_result.is_a?(Hash) ? extraction_result : {}
    end

    def call
      markdown_ko = build_markdown_ko
      llm_result = generate_summary_en
      summary_en = llm_result&.fetch(:summary, nil)
      cost_usd = llm_result&.fetch(:cost_usd, nil)
      llm_failed = summary_en.blank?

      Rails.logger.info("[Rfp::SummaryReportService] order=#{@order.id} _cost_usd=#{cost_usd.inspect}")

      {
        markdown_ko: markdown_ko,
        summary_en: llm_failed ? FAILURE_MESSAGE : summary_en,
        llm_failed: llm_failed,
        cost_usd: cost_usd,
        items: report_items,
        deadline: report_deadline
      }
    rescue => e
      Rails.logger.error("[Rfp::SummaryReportService] report build failed: #{e.class}: #{e.message}")
      nil
    end

    def build_markdown_ko
      items = @extraction_result["items"].is_a?(Array) ? @extraction_result["items"] : []
      deadline = report_deadline || "-"
      lines = [
        "건명: #{display(@order.title)}",
        "발주처: #{display(@order.client&.name)}",
        "마감일: #{display(deadline)}",
        "품목 수: #{items.size}",
        "분석 신뢰도: #{display(@extraction_result['confidence'])}",
        ""
      ]

      if items.empty?
        lines << "품목 없음"
      else
        lines.concat([
          "| # | 품목 | 모델 | 사양 | 수량 | 단위 | 납기 | 인증 |",
          "|---:|---|---|---|---:|---|---|---|"
        ])
        items.each_with_index do |item, index|
          lines << "| #{index + 1} | #{table_value(item['name'])} | #{table_value(item['model'])} | #{table_value(item['spec'])} | #{table_value(item['quantity'])} | #{table_value(item['unit'])} | #{table_value(item['delivery_date'])} | #{table_value(item['certification'])} |"
        end
      end

      checklist_lines = build_checklist_lines
      lines.concat(["", "## 체크리스트", *checklist_lines]) if checklist_lines.any?

      ambiguities = @extraction_result["ambiguities"]
      if ambiguities.is_a?(Array) && ambiguities.any?
        lines.concat(["", "## 확인 필요", *ambiguities.map { |value| "- #{value}" }])
      end

      lines.join("\n")
    rescue => e
      Rails.logger.error("[Rfp::SummaryReportService] Korean markdown build failed: #{e.class}: #{e.message}")
      raise
    end

    def generate_summary_en
      token_info = ClaudeTokenResolver.resolve
      unless token_info
        Rails.logger.error("[Rfp::SummaryReportService] Claude token unavailable")
        return nil
      end

      response = make_request(token_info, llm_payload)
      return nil unless response

      summary = response.dig("content", 0, "text").to_s.strip
      return nil if summary.blank?

      usage = response["usage"] || {}
      cost = (usage["input_tokens"].to_i * 1.0 + usage["output_tokens"].to_i * 5.0) / 1_000_000.0
      { summary: summary, cost_usd: cost.round(6) }
    rescue => e
      Rails.logger.error("[Rfp::SummaryReportService] English summary failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def report_items
      items = @extraction_result["items"].is_a?(Array) ? @extraction_result["items"] : []
      items.map do |item|
        {
          name: item["name"],
          quantity: item["quantity"],
          unit: item["unit"]
        }
      end
    end

    def report_deadline
      @extraction_result["rfp_deadline"].presence || @order.due_date.presence
    end

    def display(value)
      value.present? ? value.to_s : "-"
    end

    def table_value(value)
      display(value).gsub("|", "\\|").gsub(/\r?\n/, " ")
    end

    def build_checklist_lines
      return [] if @order.rfp_checklist_json.blank?

      values = JSON.parse(@order.rfp_checklist_json)
      return [] unless values.is_a?(Hash) && values.any?

      names = ChecklistItem.active.ordered.pluck(:code, :name).to_h
      values.map do |code, value|
        rendered = value.is_a?(Array) ? value.join(", ") : value
        "- #{names[code] || code}: #{display(rendered)}"
      end
    rescue => e
      Rails.logger.error("[Rfp::SummaryReportService] checklist parse failed: #{e.class}: #{e.message}")
      []
    end

    def llm_payload
      items = @extraction_result["items"].is_a?(Array) ? @extraction_result["items"] : []
      item_lines = items.map do |item|
        "- #{display(item['name'])}; quantity: #{display(item['quantity'])} #{display(item['unit'])}; delivery: #{display(item['delivery_date'])}; certification: #{display(item['certification'])}"
      end
      user_message = [
        "Client: #{display(@order.client&.name)}",
        "Deadline: #{display(report_deadline)}",
        "Requested items:",
        *item_lines
      ].join("\n")

      {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: user_message }]
      }
    end

    def make_request(token_info, payload)
      require "net/http"
      require "uri"
      require "json"

      uri = URI(API_URL)
      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["anthropic-version"] = API_VERSION
      if token_info[:auth] == :bearer
        request["Authorization"] = "Bearer #{token_info[:key]}"
      else
        request["x-api-key"] = token_info[:key]
      end
      request.body = payload.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response = http.request(request)
      unless response.code.to_i == 200
        body = response.body.to_s.slice(0, 500)
        Rails.logger.error("[Rfp::SummaryReportService] HTTP #{response.code}: #{body}")
        Rails.logger.error("[Rfp::SummaryReportService] ❗ Anthropic API 잔액 부족") if body.match?(/credit|balance|insufficient|quota/i)
        return nil
      end

      JSON.parse(response.body)
    rescue => e
      Rails.logger.error("[Rfp::SummaryReportService] HTTP request failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
