# frozen_string_literal: true

class QuoteAttachmentClassifier
  POSITIVE_KEYWORDS = %w[RFQ QUO QUOTE QUOTATION INQUIRY BOQ MULKIYA MTR].freeze
  NEGATIVE_KEYWORDS = %w[INVOICE RECEIPT CONTRACT NDA LICENSE AGREEMENT].freeze

  POSITIVE_MIMES = %w[
    application/pdf image/png image/jpeg
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze

  NEGATIVE_MIME_PREFIXES = %w[audio/ video/].freeze
  NEGATIVE_MIMES = %w[text/calendar application/zip].freeze

  def self.call(attachment)
    new(attachment).call
  end

  def initialize(attachment)
    @attachment = attachment
  end

  # 옵션 C (대표님 결정 2026-05-11): 모든 첨부에 [분석] 노출.
  # 단 audio/video/zip/calendar 같은 명백히 분석 불가 MIME과
  # INVOICE/CONTRACT 같은 명백한 비-견적 키워드만 차단.
  # 사용자 자율 판단으로 [분석] 클릭 — 비용 통제는 사용자 책임.
  def call
    return :not_quote if negative_mime?
    return :not_quote if negative_keyword?
    :quote_candidate
  end

  private

  def filename
    @filename ||= @attachment.filename.to_s.upcase
  end

  def mime
    @mime ||= @attachment.content_type.to_s.downcase
  end

  def positive_keyword?
    POSITIVE_KEYWORDS.any? { |kw| filename.include?(kw) }
  end

  def negative_keyword?
    NEGATIVE_KEYWORDS.any? { |kw| filename.include?(kw) }
  end

  def positive_mime?
    POSITIVE_MIMES.include?(mime)
  end

  def negative_mime?
    NEGATIVE_MIMES.include?(mime) || NEGATIVE_MIME_PREFIXES.any? { |p| mime.start_with?(p) }
  end
end
