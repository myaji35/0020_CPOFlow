# ISS-293: RFP 첨부파일 텍스트 추출 서비스
# 지원: PDF, HTML, DOCX, XLSX
# 미지원(이미지/스캔): nil 반환 → Job에서 폴백 태스크 생성
module Rfp
  class AttachmentExtractor
    MAX_CHARS = 40_000  # LLM 컨텍스트 절약용 상한

    def self.call(attachment)
      new(attachment).call
    end

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      blob = @attachment.blob
      filename = blob.filename.to_s
      content_type = blob.content_type.to_s.downcase

      result = @attachment.open do |file|
        extract(file.path, content_type, filename)
      end

      result
    rescue => e
      Rails.logger.warn("[Rfp::AttachmentExtractor] #{filename}: #{e.class}: #{e.message}")
      { text: nil, error: e.message, filename: blob.filename.to_s, content_type: content_type }
    end

    private

    def extract(path, content_type, filename)
      ext = File.extname(filename).downcase

      text = if pdf?(content_type, ext)
        extract_pdf(path)
      elsif docx?(content_type, ext)
        extract_docx(path)
      elsif xlsx?(content_type, ext)
        extract_xlsx(path)
      elsif html?(content_type, ext)
        extract_html(path)
      elsif text_plain?(content_type, ext)
        File.read(path, encoding: "utf-8", invalid: :replace, undef: :replace)
      else
        nil
      end

      text = text&.strip&.slice(0, MAX_CHARS)

      {
        text: text.presence,
        filename: filename,
        content_type: content_type,
        error: text.present? ? nil : "unsupported_format"
      }
    end

    def extract_pdf(path)
      require "pdf-reader"
      reader = PDF::Reader.new(path)
      pages_text = reader.pages.map(&:text).join("\n\n")
      pages_text.presence
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
      Rails.logger.warn("[Rfp::AttachmentExtractor] PDF read error: #{e.message}")
      nil
    end

    def extract_docx(path)
      # docx gem이 없으면 zip 직접 파싱 (word/document.xml)
      require "zip"
      text_parts = []
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("word/document.xml")
        next unless entry
        xml = entry.get_input_stream.read
        # XML 태그 제거 후 텍스트 추출
        doc = Nokogiri::XML(xml)
        doc.xpath("//w:t").each { |node| text_parts << node.text }
      end
      text_parts.join(" ").presence
    rescue => e
      Rails.logger.warn("[Rfp::AttachmentExtractor] DOCX read error: #{e.message}")
      nil
    end

    def extract_xlsx(path)
      require "roo"
      workbook = Roo::Spreadsheet.open(path, extension: :xlsx)
      rows = []
      workbook.each_with_pagename do |_name, sheet|
        sheet.each_row_streaming do |row|
          values = row.map { |cell| cell&.value.to_s.strip }.reject(&:blank?)
          rows << values.join("\t") if values.any?
        end
      end
      rows.join("\n").presence
    rescue => e
      Rails.logger.warn("[Rfp::AttachmentExtractor] XLSX read error: #{e.message}")
      nil
    end

    def extract_html(path)
      raw = File.read(path, encoding: "utf-8", invalid: :replace, undef: :replace)
      doc = Nokogiri::HTML(raw)
      doc.search("script, style").remove
      doc.text.gsub(/\s{2,}/, " ").strip.presence
    rescue => e
      Rails.logger.warn("[Rfp::AttachmentExtractor] HTML read error: #{e.message}")
      nil
    end

    # MIME + 확장자 판별 헬퍼
    def pdf?(ct, ext)
      ct.include?("pdf") || ext == ".pdf"
    end

    def docx?(ct, ext)
      ct.include?("wordprocessingml") || ct.include?("msword") || %w[.docx .doc].include?(ext)
    end

    def xlsx?(ct, ext)
      ct.include?("spreadsheetml") || ct.include?("ms-excel") || %w[.xlsx .xls .csv].include?(ext)
    end

    def html?(ct, ext)
      ct.include?("html") || ext == ".html" || ext == ".htm"
    end

    def text_plain?(ct, ext)
      ct.include?("text/plain") || ext == ".txt"
    end
  end
end
