# frozen_string_literal: true

# LAB / RFQ Auto Phase 3 — Vision 모드 품목 추출.
# 텍스트 추출 실패 또는 LLM이 0개 반환했을 때 PDF/이미지를 직접 Claude Sonnet에 전달.
#
# 호출:
#   raw = RfqAuto::VisionItemExtractor.new(order, pages_cap: 5).call
#   # => { items: [...], cost_usd: 0.02, model: "claude-sonnet-4-6", page_count: 3 }
#
# 비용:
#   Sonnet 4.6 — input $3/1M, output $15/1M tokens
#   이미지 1장 ≈ 4,500 token (A4 200dpi)
#   페이지 5장 cap 시 1건 당 $0.030 ~ $0.100 예상
#
# 잔액 부족 시: AnthropicCreditError 발생 → 컨트롤러가 사용자에게 충전 요청 보고
require "base64"
require "open3"
require "tmpdir"
require "fileutils"

module RfqAuto
  class VisionItemExtractor
    MODEL = ENV.fetch("RFQ_VISION_MODEL", "claude-sonnet-4-6")
    DEFAULT_PAGES_CAP = 5
    INPUT_PER_MTOK   = 3.00   # USD per 1M input tokens (Sonnet 4.6)
    OUTPUT_PER_MTOK  = 15.00

    class AnthropicCreditError < StandardError; end
    class VisionUnavailableError < StandardError; end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You extract procurement RFQ line items from images of quotation request documents.
      Return ONLY a JSON object with this exact shape:
      {
        "items": [
          {"name": "...", "model": "...", "spec": "...", "quantity": "...", "unit": "...", "certification": "...", "manufacturer": "...", "brand": "...", "part_no": "...", "remarks": "..."}
        ]
      }
      Rules:
      - "name" is required (item/product name in English if possible).
      - Include model number, specs, qty, unit, certification (KS/CE/API/ATEX/ISO) if present.
      - "manufacturer": OEM/maker name (e.g. "Sika", "3M", "Hyosung"). If not identified, return "".
      - "brand": brand/series label if distinct from manufacturer (e.g. "Sika Pro"). If not identified, return "".
      - "part_no": part/SKU number if separate from model (e.g. "SK-100-A"). If not identified, return "".
      - "remarks": free-form notes (delivery condition, packaging, QC requirement). If not identified, return "".
      - If document is NOT a procurement request (e.g. registration form, marketing), return {"items": []}.
      - Output JSON only, no commentary.
    PROMPT

    def initialize(order, pages_cap: DEFAULT_PAGES_CAP)
      @order = order
      @pages_cap = pages_cap
    end

    def call
      images = extract_images
      return { items: [], cost_usd: 0.0, model: MODEL, page_count: 0, reason: "no_images" } if images.empty?

      input_tokens, output_tokens, items = call_anthropic(images)
      cost = (input_tokens.to_f * INPUT_PER_MTOK / 1_000_000) +
             (output_tokens.to_f * OUTPUT_PER_MTOK / 1_000_000)

      {
        items:        items,
        cost_usd:     cost.round(4),
        model:        MODEL,
        page_count:   images.size,
        input_tokens: input_tokens,
        output_tokens: output_tokens
      }
    ensure
      cleanup_tempdir
    end

    private

    # 첨부 PDF/이미지 → PNG 페이지 배열. pdftoppm 사용 (poppler-utils 필요).
    # PDF가 아닌 첨부(이미지 자체)는 그대로 인코딩.
    def extract_images
      @tmpdir = Dir.mktmpdir("rfq-vision-")
      results = []

      @order.attachments.each do |att|
        break if results.size >= @pages_cap
        filename = att.blob.filename.to_s
        next unless filename.match?(/\.(pdf|png|jpg|jpeg|gif|webp)$/i)
        next if att.blob.byte_size > 20.megabytes  # 큰 파일 skip

        # 파일을 임시로 저장
        local_path = File.join(@tmpdir, filename.gsub(/[^a-zA-Z0-9._-]/, "_"))
        File.binwrite(local_path, att.blob.download)

        if filename.match?(/\.pdf$/i)
          out_prefix = File.join(@tmpdir, "page-#{att.id}")
          remaining = @pages_cap - results.size
          # pdftoppm: -r 150 dpi (token 절약), -f 1 -l N (페이지 제한)
          cmd = [ "pdftoppm", "-png", "-r", "150", "-f", "1", "-l", remaining.to_s, local_path, out_prefix ]
          stdout, stderr, status = Open3.capture3(*cmd)
          unless status.success?
            Rails.logger.warn "[VisionItemExtractor] pdftoppm 실패 (#{filename}): #{stderr.truncate(200)}"
            next
          end
          Dir.glob("#{out_prefix}-*.png").sort.each do |png|
            break if results.size >= @pages_cap
            results << encode_image(png)
          end
        else
          results << encode_image(local_path)
        end
      end

      results
    end

    def encode_image(path)
      mime = case File.extname(path).downcase
             when ".png" then "image/png"
             when ".jpg", ".jpeg" then "image/jpeg"
             when ".gif" then "image/gif"
             when ".webp" then "image/webp"
             else "image/png"
             end
      {
        type: "image",
        source: {
          type: "base64",
          media_type: mime,
          data: Base64.strict_encode64(File.binread(path))
        }
      }
    end

    def cleanup_tempdir
      FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
    rescue StandardError
      nil
    end

    def call_anthropic(images)
      token_info = ClaudeTokenResolver.resolve
      raise VisionUnavailableError, "Anthropic API 키 미설정" if token_info.nil?

      client = Anthropic::Client.new(api_key: token_info[:key])

      content = images.map { |img| img } + [
        { type: "text", text: "Extract procurement line items from these document pages. Return JSON only." }
      ]

      response = client.messages.create(
        model:       MODEL,
        max_tokens:  2048,
        system:      SYSTEM_PROMPT,
        messages:    [ { role: "user", content: content } ]
      )

      input_tokens  = response.usage&.input_tokens.to_i
      output_tokens = response.usage&.output_tokens.to_i
      text = response.content.is_a?(Array) ? response.content.first&.text.to_s : response.content.to_s

      json = extract_json(text)
      items = (json.is_a?(Hash) ? json["items"] : nil) || []

      [ input_tokens, output_tokens, items ]
    rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError => e
      msg = e.message.to_s
      if msg.match?(/credit|quota|insufficient|balance/i)
        raise AnthropicCreditError, "Anthropic 잔액 부족 — 충전 후 재시도 (#{msg.truncate(120)})"
      end
      raise
    end

    def extract_json(text)
      # Sonnet은 보통 ```json ... ``` 또는 plain JSON 반환
      cleaned = text.to_s.strip
      cleaned = cleaned.sub(/\A```json\s*/, "").sub(/```\z/, "").strip if cleaned.start_with?("```")
      JSON.parse(cleaned)
    rescue JSON::ParserError
      # 본문 안 어디든 첫 { … } 블록 추출 시도
      m = text.to_s.match(/\{.*\}/m)
      m ? (JSON.parse(m[0]) rescue {}) : {}
    end
  end
end
