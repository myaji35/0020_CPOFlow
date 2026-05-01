module DocumentAttachable
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/msword
    image/jpeg image/pjpeg image/png image/gif image/webp image/heic image/heif
    application/octet-stream
  ].freeze

  DENY_EXTENSIONS = %w[exe bat cmd com sh ps1 msi dll jar js vbs scr cpl hta reg py pyc rb pl php app deb rpm apk ipa].freeze
  MAX_SIZE = 25.megabytes

  included do
    has_many_attached :documents
    validate :validate_documents_safety
  end

  private

  def validate_documents_safety
    return unless documents.attached?

    documents.each do |doc|
      blob = doc.blob
      ext = File.extname(blob.filename.to_s).delete(".").downcase
      if DENY_EXTENSIONS.include?(ext)
        errors.add(:documents, "허용되지 않은 파일 형식: .#{ext} (#{blob.filename})")
        doc.purge_later if blob.persisted?
        next
      end
      ctype = blob.content_type.to_s.downcase
      if ctype != "application/octet-stream" && !ALLOWED_CONTENT_TYPES.include?(ctype)
        errors.add(:documents, "허용되지 않은 MIME: #{ctype}")
        doc.purge_later if blob.persisted?
        next
      end
      if blob.byte_size > MAX_SIZE
        mb = (blob.byte_size.to_f / 1.megabyte).round(1)
        errors.add(:documents, "파일 크기 초과 (#{mb}MB > #{MAX_SIZE / 1.megabyte}MB)")
        doc.purge_later if blob.persisted?
      end
    end
  end
end
