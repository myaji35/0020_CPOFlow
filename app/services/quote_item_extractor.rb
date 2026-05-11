# frozen_string_literal: true

require "base64"
require "open3"
require "tmpdir"

# Sonnet 4.6 Vision 으로 PDF/이미지 첨부파일을 분석해 품목 7컬럼 JSON 배열 추출.
#
# 호출:
#   result = QuoteItemExtractor.new(attachment).call
#   # => { items: [...], cost_usd: 0.02, llm_model: "claude-sonnet-4-6", page_count: 3 }
#
# 잔액 부족 시: AnthropicCreditError 발생
# 파싱/CLI 실패 시: ExtractionError 발생
class QuoteItemExtractor
  MODEL = ENV.fetch("QUOTE_EXTRACTOR_MODEL", "claude-sonnet-4-6")
  DEFAULT_PAGES_CAP = 5
  INPUT_PER_MTOK   = 3.00   # USD per 1M input tokens (Sonnet 4.6)
  OUTPUT_PER_MTOK  = 15.00

  class AnthropicCreditError < StandardError; end
  class ExtractionError < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You extract procurement RFQ line items from images of quotation request documents.
    Return ONLY a JSON object with this exact shape:
    {
      "items": [
        {
          "item": "...",
          "description": "...",
          "model_part_no": "...",
          "manufacturer_brand": "...",
          "unit": "...",
          "qty": "...",
          "remarks": "..."
        }
      ]
    }
    Rules:
    - "item" is required (item/product name, original language preserved).
    - "description" preserves multi-line specs (DIMENSIONS / MATERIAL / CAPACITY / COLOR / etc).
    - "model_part_no": model number or part/SKU (e.g. "5004-BK").
    - "manufacturer_brand": OEM/maker or brand (e.g. "ENPAC").
    - "unit": EA / KG / SET / M / etc.
    - "qty": numeric or numeric-with-unit string.
    - "remarks": free-form notes (delivery condition, packaging, QC).
    - If document is NOT a procurement RFQ/quotation request, return {"items": []}.
    - Output JSON only, no commentary.
  PROMPT

  def initialize(attachment, pages_cap: DEFAULT_PAGES_CAP)
    @attachment = attachment
    @pages_cap = pages_cap
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    images = render_pages
    return empty_result(reason: "no_images") if images.empty?

    input_tokens, output_tokens, items = call_anthropic(images)
    cost = (input_tokens.to_f * INPUT_PER_MTOK / 1_000_000) +
           (output_tokens.to_f * OUTPUT_PER_MTOK / 1_000_000)
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    {
      items: items,
      cost_usd: cost.round(4),
      llm_model: MODEL,
      page_count: images.size,
      latency_ms: latency_ms
    }
  end

  private

  def empty_result(reason:)
    {
      items: [],
      cost_usd: 0.0,
      llm_model: MODEL,
      page_count: 0,
      reason: reason,
      latency_ms: 0
    }
  end

  def render_pages
    return [] unless @attachment.respond_to?(:blob) && @attachment.blob.present?

    case @attachment.content_type
    when "application/pdf"
      render_pdf_pages
    when /^image\//
      [base64_image(@attachment.download)]
    else
      []
    end
  end

  def render_pdf_pages
    Dir.mktmpdir do |dir|
      pdf_path = File.join(dir, "in.pdf")
      File.binwrite(pdf_path, @attachment.download)
      out_prefix = File.join(dir, "page")
      _stdout, stderr, status = Open3.capture3(
        "pdftoppm", "-png", "-r", "150",
        "-f", "1", "-l", @pages_cap.to_s,
        pdf_path, out_prefix
      )
      raise ExtractionError, "pdftoppm failed: #{stderr}" unless status.success?

      Dir.glob("#{out_prefix}-*.png").sort.map { |p| base64_image(File.binread(p)) }
    end
  end

  def base64_image(bytes)
    Base64.strict_encode64(bytes)
  end

  def call_anthropic(images)
    client = ClaudeTokenResolver.create_client
    raise AnthropicCreditError, "Anthropic API key not configured" if client.nil?

    content = images.map do |b64|
      { type: "image", source: { type: "base64", media_type: "image/png", data: b64 } }
    end
    content << { type: "text", text: 'Extract items as JSON. Return {"items":[...]}' }

    resp = client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: content }]
    )

    text = resp.content.is_a?(Array) ? resp.content.first&.text.to_s : resp.content.to_s
    json_str = text.match(/\{.*\}/m)&.to_s
    raise ExtractionError, "No JSON in LLM response" if json_str.nil?

    parsed = JSON.parse(json_str)
    items = Array(parsed["items"])
    [resp.usage&.input_tokens.to_i, resp.usage&.output_tokens.to_i, items]
  rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError => e
    raise AnthropicCreditError, e.message.to_s
  rescue Anthropic::Errors::APIError => e
    msg = e.message.to_s
    if msg.include?("insufficient") || msg.include?("401") || msg.match?(/credit/i)
      raise AnthropicCreditError, msg
    end
    raise ExtractionError, "LLM call failed: #{msg}"
  rescue JSON::ParserError => e
    raise ExtractionError, "Invalid JSON: #{e.message}"
  end
end
