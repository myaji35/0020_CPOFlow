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

  def call
    return :not_quote if negative_mime?
    return :not_quote if negative_keyword?
    return :quote_candidate if positive_keyword?
    return :ambiguous if positive_mime?
    :not_quote
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
