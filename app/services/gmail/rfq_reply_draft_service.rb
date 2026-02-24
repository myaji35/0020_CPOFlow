# frozen_string_literal: true

module Gmail
  # Gemini API로 RFQ 수신 확인 답변 초안 자동 생성
  #
  # Usage:
  #   Gmail::RfqReplyDraftService.generate!(order)
  #   # => "Dear [Name],\nThank you for your RFQ..."
  class RfqReplyDraftService
    GEMINI_MODEL = "gemini-2.0-flash"

    def self.generate!(order)
      new(order).generate!
    end

    def initialize(order)
      @order = order
    end

    def generate!
      return cached_draft if @order.reply_draft.present?

      draft = call_gemini_api
      @order.update_column(:reply_draft, draft) if draft.present?
      draft
    rescue => e
      Rails.logger.error "[RfqReplyDraft] Error: #{e.class} — #{e.message}"
      nil
    end

    private

    def cached_draft
      @order.reply_draft
    end

    def call_gemini_api
      api_key = Rails.application.credentials.dig(:gemini, :api_key)
      return nil if api_key.blank?

      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{GEMINI_MODEL}:generateContent?key=#{api_key}")
      body = {
        contents: [ { parts: [ { text: build_prompt } ] } ],
        generationConfig: {
          temperature:     0.3,
          maxOutputTokens: 800
        }
      }

      response = Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
      data = JSON.parse(response.body)
      data.dig("candidates", 0, "content", "parts", 0, "text")&.strip
    rescue => e
      Rails.logger.error "[RfqReplyDraft] Gemini API error: #{e.message}"
      nil
    end

    def build_prompt
      language = detect_language
      business_days = business_reply_date

      <<~PROMPT
        You are a procurement specialist at AtoZ2010 Inc., a construction materials supplier.
        Write a professional RFQ acknowledgment reply email.

        EMAIL RECEIVED:
        From: #{@order.original_email_from}
        Subject: #{@order.original_email_subject}
        Body preview: #{@order.original_email_body.to_s.first(500)}

        REPLY REQUIREMENTS:
        - Language: #{language} (match the language of the incoming email)
        - Tone: Professional, warm, brief
        - Content:
          1. Thank them for the RFQ inquiry
          2. Confirm receipt
          3. State we will review and respond by #{business_days}
          4. Ask them to contact us if urgent
        - DO NOT include pricing, commitments, or specific product details
        - Keep it under 150 words
        - Sign off as: "AtoZ2010 Procurement Team"

        Output ONLY the email body text (no subject line, no formatting instructions).
      PROMPT
    end

    def detect_language
      body = @order.original_email_body.to_s + @order.original_email_subject.to_s
      arabic_count = body.scan(/[\u0600-\u06FF]/).length
      korean_count = body.scan(/[\uAC00-\uD7A3]/).length
      total_chars  = body.length.to_f

      if arabic_count / total_chars > 0.1
        "Arabic (ar)"
      elsif korean_count / total_chars > 0.1
        "Korean (ko)"
      else
        "English (en)"
      end
    end

    def business_reply_date
      target = Date.today
      added  = 0
      while added < 2
        target += 1
        added += 1 unless target.saturday? || target.sunday?
      end
      target.strftime("%B %d, %Y")
    end
  end
end
