# frozen_string_literal: true

module Ecount
  # CSV(UTF-8/EUC-KR) 또는 XLSX 파일을 파싱하여 Array<Hash> 반환
  # 헤더 기반 컬럼 매핑 (컬럼 순서 무관)
  class EcountParser
    # 한글/영문 헤더 → 내부 심볼 키 정규화
    HEADER_MAP = {
      # 품목 (Products)
      "품목코드"    => :ecount_code,
      "품목명"      => :name,
      "규격"        => :description,
      "단위"        => :unit,
      "품목분류"    => :category,
      "브랜드"      => :brand,
      "단가"        => :unit_price,
      "통화"        => :currency,
      "사용여부"    => :active,
      # 거래처 (Suppliers)
      "거래처코드"  => :ecount_code,
      "거래처명"    => :name,
      "국가"        => :country,
      "이메일"      => :contact_email,
      "담당자이메일"=> :contact_email,
      "연락처"      => :contact_phone,
      "비고"        => :notes,
      # 거래 이력 (Orders)
      "거래번호"    => :source_ref,
      "납기일"      => :due_date,
      "수량"        => :quantity,
      "거래금액"    => :estimated_value,
      "거래상태"    => :ecount_status,
      "담당자"      => :customer_name,
      # 영문 헤더도 지원
      "code"        => :ecount_code,
      "name"        => :name,
      "unit"        => :unit,
      "price"       => :unit_price,
      "currency"    => :currency,
      "active"      => :active,
      "country"     => :country,
      "email"       => :contact_email,
      "phone"       => :contact_phone,
      "notes"       => :notes,
    }.freeze

    def initialize(file_path)
      @path = file_path.to_s
      @ext  = File.extname(@path).downcase
    end

    # 전체 파싱 → Array<Hash>
    def parse
      case @ext
      when ".csv" then parse_csv
      when ".xlsx", ".xls" then parse_xlsx
      else raise ArgumentError, "지원하지 않는 파일 형식: #{@ext}"
      end
    end

    # 상위 n행만 미리보기
    def preview(n: 10)
      parse.first(n)
    end

    private

    def parse_csv
      encoding = detect_csv_encoding
      rows     = []
      headers  = nil

      CSV.foreach(@path, encoding: encoding, liberal_parsing: true) do |row|
        if headers.nil?
          headers = normalize_headers(row.map(&:to_s))
          next
        end
        hash = build_hash(headers, row)
        rows << hash if hash.values.any?(&:present?)
      end
      rows
    rescue CSV::MalformedCSVError => e
      raise "CSV 파싱 오류: #{e.message}"
    end

    def parse_xlsx
      require "roo"
      xlsx = Roo::Spreadsheet.open(@path, extension: :xlsx)
      sheet = xlsx.sheet(0)

      headers = normalize_headers(sheet.row(1).map { |c| c.to_s.strip })
      rows    = []

      (2..sheet.last_row).each do |i|
        hash = build_hash(headers, sheet.row(i))
        rows << hash if hash.values.any?(&:present?)
      end
      rows
    rescue => e
      raise "XLSX 파싱 오류: #{e.message}"
    end

    # EUC-KR / UTF-8 자동 감지
    def detect_csv_encoding
      raw = File.read(@path, encoding: "binary").force_encoding("UTF-8")
      raw.valid_encoding? ? "UTF-8" : "EUC-KR:UTF-8"
    rescue
      "UTF-8"
    end

    def normalize_headers(headers)
      headers.map do |h|
        key = h.to_s.strip.downcase.gsub(/\s+/, "")
        # 원래 헤더 문자열로 먼저 매핑 시도
        HEADER_MAP[h.to_s.strip] || HEADER_MAP[key] || key.to_sym
      end
    end

    def build_hash(headers, row)
      headers.zip(row.map { |v| v.to_s.strip.presence }).to_h
             .reject { |k, _| k.nil? || k.to_s.empty? }
    end
  end
end
