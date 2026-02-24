# frozen_string_literal: true

# TranslationService: Gemini API를 이용한 텍스트 번역
# 번역 결과는 Order 모델에 캐싱하여 반복 API 호출 방지
#
# credentials 설정:
#   bin/rails credentials:edit
#   gemini:
#     api_key: "AIza..."
class TranslationService
  GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent"

  def self.translate(text)
    return nil if text.blank?
    return text if predominantly_korean?(text)

    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    if api_key.blank?
      Rails.logger.warn "[TranslationService] Gemini API key not configured (credentials.gemini.api_key)"
      return nil
    end

    uri = URI("#{GEMINI_ENDPOINT}?key=#{api_key}")
    prompt = <<~PROMPT
      You are a professional translator for a procurement company.
      Translate the following business email to natural Korean.

      Rules:
      - Output ONLY the translated Korean text. No explanations, no markdown.
      - Keep these unchanged: RFQ numbers, PO numbers, quote numbers, product codes, part numbers, prices, quantities, units, company names, person names, email addresses, URLs.
      - Translate English business terms naturally (e.g. "quotation" → "견적서", "delivery" → "납기/납품", "purchase order" → "발주서").
      - If a sentence is already in Korean, keep it as-is.
      - Preserve the original paragraph structure and line breaks.

      Email text:
      #{text}
    PROMPT

    body = {
      contents: [
        { parts: [ { text: prompt } ] }
      ],
      generationConfig: { temperature: 0.1, maxOutputTokens: 2048 }
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body

    response = http.request(request)
    data = JSON.parse(response.body)

    data.dig("candidates", 0, "content", "parts", 0, "text")
  rescue => e
    Rails.logger.error "[TranslationService] Gemini error: #{e.message}"
    nil
  end

  # Order의 번역 컬럼을 채우고 저장 (없을 때만 번역)
  def self.translate_order!(order)
    changed = false

    if order.translated_subject.blank? && order.original_email_subject.present?
      translated = translate(order.original_email_subject)
      if translated.present?
        order.translated_subject = translated.strip
        changed = true
      end
    end

    body_source = order.original_email_body.presence || order.description
    if order.translated_body.blank? && body_source.present?
      translated = translate(body_source)
      if translated.present?
        order.translated_body = translated.strip
        changed = true
      end
    end

    order.save(validate: false) if changed
    order
  end

  private

  # 한국어 비율 감지: 한글 문자가 전체 알파벳 문자의 70% 이상이면 이미 한국어로 판단
  # 영문 본문에 한글 단어 1~2개가 섞인 경우는 번역 대상으로 처리
  def self.predominantly_korean?(text)
    korean_chars = text.scan(/[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]/).length
    alpha_chars  = text.scan(/[a-zA-Z\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]/).length
    return false if alpha_chars < 10  # 너무 짧으면 번역 시도
    korean_chars.to_f / alpha_chars >= 0.7
  end
end
