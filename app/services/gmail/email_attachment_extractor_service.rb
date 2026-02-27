# frozen_string_literal: true

module Gmail
  # Gmail 이메일에서 첨부파일과 링크를 추출하는 서비스
  #
  # Usage:
  #   extractor = Gmail::EmailAttachmentExtractorService.new(gmail_svc, msg, order)
  #   extractor.extract_and_attach!
  class EmailAttachmentExtractorService
    MAX_ATTACHMENT_SIZE = 20.megabytes
    SUPPORTED_MIME_TYPES = %w[
      application/pdf
      application/vnd.ms-excel
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/msword
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      image/jpeg image/png image/gif
      text/plain text/csv
    ].freeze

    def initialize(gmail_service, gmail_message, order)
      @svc     = gmail_service
      @message = gmail_message
      @order   = order
    end

    def extract_and_attach!
      attachment_infos = []
      links = extract_links_from_body

      # 첨부파일 처리
      attachments = find_attachments(@message.payload)
      attachments.each do |att|
        info = process_attachment(att)
        attachment_infos << info if info
      end

      # Order에 메타데이터 저장
      @order.update_columns(
        attachment_urls: attachment_infos.to_json,
        extracted_links: links.to_json
      )

      { attachments: attachment_infos, links: links }
    rescue => e
      Rails.logger.error "[AttachmentExtractor] Error for order ##{@order.id}: #{e.message}"
      { attachments: [], links: [] }
    end

    private

    def find_attachments(payload)
      attachments = []
      return attachments unless payload

      if payload.filename.present? && payload.body&.attachment_id
        attachments << payload
      end

      if payload.parts
        payload.parts.each do |part|
          attachments.concat(find_attachments(part))
        end
      end

      attachments
    end

    def process_attachment(part)
      return nil if part.body.attachment_id.blank?
      return nil unless supported_mime_type?(part.mime_type)
      return nil if (part.body.size || 0) > MAX_ATTACHMENT_SIZE

      # Gmail API에서 첨부파일 데이터 다운로드
      attachment_data = @svc.fetch_attachment(
        @message.id,
        part.body.attachment_id
      )
      return nil unless attachment_data

      # ActiveStorage에 저장
      blob = ActiveStorage::Blob.create_and_upload!(
        io:           StringIO.new(attachment_data),
        filename:     part.filename,
        content_type: part.mime_type
      )

      @order.attachments.attach(blob)

      {
        filename:     part.filename,
        mime_type:    part.mime_type,
        size:         part.body.size,
        blob_key:     blob.key,
        signed_url:   Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      }
    rescue => e
      Rails.logger.warn "[AttachmentExtractor] Failed to process #{part.filename}: #{e.message}"
      nil
    end

    def extract_links_from_body
      body = extract_text_body(@message.payload)
      return [] if body.blank?

      # URL 패턴 추출
      urls = body.scan(%r{https?://[^\s<>"'\)]+}).uniq
      urls.select { |url| url.length < 500 }.first(10)  # 최대 10개, 500자 이하
    end

    # SAP Ariba 포털 이벤트 링크를 HTML/plain body에서 추출
    # 정규식으로 ariba.com 포함 URL을 찾아 첫 번째 반환
    def extract_ariba_event_link
      ariba_url_pattern = /(https?:\/\/[^\s<>"']*ariba\.com[^\s<>"']*)/i

      # HTML body 우선 탐색
      html_body = extract_html_body(@message.payload)
      if html_body.present?
        match = html_body.match(ariba_url_pattern)
        return match[1] if match
      end

      # plain text body 폴백
      plain_body = extract_text_body(@message.payload)
      match = plain_body.match(ariba_url_pattern)
      match ? match[1] : nil
    end


    def extract_text_body(payload)
      return "" unless payload

      if payload.mime_type == "text/plain" && payload.body&.data
        Base64.urlsafe_decode64(payload.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      elsif payload.parts
        plain = payload.parts.find { |p| p.mime_type == "text/plain" }
        return "" unless plain&.body&.data
        Base64.urlsafe_decode64(plain.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      else
        ""
      end
    rescue
      ""
    end

    def extract_html_body(payload)
      return "" unless payload

      if payload.mime_type == "text/html" && payload.body&.data
        Base64.urlsafe_decode64(payload.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      elsif payload.parts
        html_part = payload.parts.find { |p| p.mime_type == "text/html" }
        return "" unless html_part&.body&.data
        Base64.urlsafe_decode64(html_part.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      else
        ""
      end
    rescue
      ""
    end

    def supported_mime_type?(mime_type)
      SUPPORTED_MIME_TYPES.any? { |supported| mime_type.to_s.start_with?(supported) }
    end
  end
end
