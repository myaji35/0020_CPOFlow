# ISS-333: RFP 분석 대상 첨부파일 사전 필터
# 목적: ariba_login_capture, 빈 페이지 캡처 등 노이즈 제거 (production 1000건 분석 결과 58%가 노이즈)
# 입력: ActiveStorage::Attachment
# 출력: { relevant: Boolean, reason: String }
module Rfp
  class AttachmentRelevanceFilter
    # ariba_page_*.pdf 등 자동 캡처 패턴
    NOISE_FILENAME_PATTERNS = [
      /\Aariba_page_\d+\.(pdf|html?)\z/i,
      /\Aariba_login/i,
      /captcha/i,
      /screenshot[-_]?\d+/i,
      /\Apage[-_]?capture/i
    ].freeze

    # PDF Title 메타데이터로 자동 캡처 식별
    NOISE_PDF_TITLES = [
      "Ariba On-Demand Site",
      "Ariba Network",
      "Ariba Sourcing"
    ].freeze

    def self.call(attachment)
      new(attachment).call
    end

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      filename = @attachment.blob.filename.to_s
      return reject("filename pattern: ariba_page/login/captcha") if filename_noise?(filename)

      content_type = @attachment.blob.content_type.to_s
      byte_size = @attachment.blob.byte_size.to_i

      if pdf?(content_type, filename) && pdf_noise_title?
        return reject("pdf title: Ariba On-Demand Site (login capture)")
      end

      return reject("size < 2KB") if byte_size < 2_048

      { relevant: true, reason: "passes filter" }
    rescue => e
      Rails.logger.warn("[Rfp::AttachmentRelevanceFilter] #{filename}: #{e.class}: #{e.message}")
      { relevant: true, reason: "filter error, default include" }
    end

    private

    def reject(reason)
      { relevant: false, reason: reason }
    end

    def filename_noise?(filename)
      NOISE_FILENAME_PATTERNS.any? { |pat| filename =~ pat }
    end

    def pdf?(content_type, filename)
      content_type.to_s.include?("pdf") || File.extname(filename).downcase == ".pdf"
    end

    def pdf_noise_title?
      @attachment.open do |file|
        head = file.read(2048).to_s
        NOISE_PDF_TITLES.any? { |title| head.include?("/Title (#{title}") }
      end
    rescue => e
      filename = @attachment.blob.filename.to_s rescue "(unknown filename)"
      Rails.logger.warn("[Rfp::AttachmentRelevanceFilter] pdf_noise_title? #{filename}: #{e.class}: #{e.message}")
      false
    end
  end
end
