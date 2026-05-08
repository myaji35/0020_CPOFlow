# frozen_string_literal: true

# RFQ Auto C2 — Tesseract OCR 텍스트 추출.
# 호출:
#   text = RfqAuto::OcrTextExtractor.new(order, max_pages: 5).call
#   # => "추출된 텍스트..." 또는 nil (실패/미설치)
#
# 흐름:
#   1. PDF는 pdftoppm으로 PNG 변환 (max_pages 페이지)
#   2. tesseract -l kor+eng로 OCR
#   3. 모든 페이지 텍스트 합쳐 반환
#
# 비용: $0 (자체 서버 CPU 사용)
# 의존: poppler-utils + tesseract-ocr + tesseract-ocr-eng + tesseract-ocr-kor
require "open3"
require "tmpdir"
require "fileutils"

module RfqAuto
  class OcrTextExtractor
    DEFAULT_MAX_PAGES = 5

    def initialize(order, max_pages: DEFAULT_MAX_PAGES)
      @order = order
      @max_pages = max_pages
    end

    def call
      return nil unless tesseract_available?

      texts = []
      Dir.mktmpdir("rfq-ocr-") do |tmpdir|
        @order.attachments.each do |att|
          break if texts.size >= @max_pages
          fname = att.blob.filename.to_s
          next unless fname.match?(/\.(pdf|png|jpg|jpeg|tiff|bmp)$/i)
          next if att.blob.byte_size > 30.megabytes

          local_path = File.join(tmpdir, fname.gsub(/[^a-zA-Z0-9._-]/, "_"))
          File.binwrite(local_path, att.blob.download)

          if fname.match?(/\.pdf$/i)
            png_pages = pdf_to_pngs(local_path, tmpdir, "page-#{att.id}")
            png_pages.each do |png|
              break if texts.size >= @max_pages
              ocr = run_tesseract(png)
              texts << ocr if ocr.present?
            end
          else
            ocr = run_tesseract(local_path)
            texts << ocr if ocr.present?
          end
        end
      end

      combined = texts.join("\n\n--- OCR PAGE BREAK ---\n\n").strip
      combined.presence
    rescue StandardError => e
      Rails.logger.warn "[OcrTextExtractor] #{e.class}: #{e.message}"
      nil
    end

    private

    def tesseract_available?
      system("which tesseract > /dev/null 2>&1") &&
        system("which pdftoppm > /dev/null 2>&1")
    end

    def pdf_to_pngs(pdf_path, tmpdir, prefix)
      out = File.join(tmpdir, prefix)
      _, _, status = Open3.capture3(
        "pdftoppm", "-png", "-r", "200",
        "-f", "1", "-l", @max_pages.to_s,
        pdf_path, out
      )
      return [] unless status.success?
      Dir.glob("#{out}-*.png").sort
    end

    def run_tesseract(image_path)
      stdout, _stderr, status = Open3.capture3(
        "tesseract", image_path, "stdout",
        "-l", "kor+eng",
        "--psm", "3"  # auto page segmentation
      )
      status.success? ? stdout.strip : nil
    rescue StandardError
      nil
    end
  end
end
