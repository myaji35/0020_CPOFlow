# frozen_string_literal: true

# LAB / RFQ Auto — 양식별 정규식 패턴 매칭 (Phase 2-A)
#
# config/rfq_auto/nawah_patterns.json 의 패턴 라이브러리를 로드해
# 첨부 텍스트에서 양식 식별 + 필드 추출 + MUST/NICE 컴플라이언스 체크를 수행.
#
# Sonnet 호출 전 1차 추출 — 정규식만으로 82% 커버되는 NAWAH/ENEC 양식 빠른 처리.
#
# 사용:
#   matcher = RfqAuto::FormatMatcher.new(text)
#   matcher.format_name         # => "NAWAH PO Standard" or nil
#   matcher.fields              # => { po_number: "4500020346", po_date: "13 Apr 2026", ... }
#   matcher.must_comply         # => [{category:, severity:, what_to_do:, example:}, ...]
#   matcher.nice_to_have        # => [{type:, what_it_means:, example:}, ...]
#   matcher.invalid?            # => true (Ariba 로그인 페이지 같은 무효 문서)
module RfqAuto
  class FormatMatcher
    PATTERNS_PATH = Rails.root.join("config/rfq_auto/nawah_patterns.json")

    class << self
      def patterns
        @patterns ||= load_patterns
      end

      def reload!
        @patterns = load_patterns
      end

      private

      def load_patterns
        return {} unless File.exist?(PATTERNS_PATH)
        JSON.parse(File.read(PATTERNS_PATH))
      rescue JSON::ParserError => e
        Rails.logger.warn("[RfqAuto::FormatMatcher] patterns parse failed: #{e.message}")
        {}
      end
    end

    attr_reader :text

    def initialize(text)
      @text = text.to_s
    end

    def format_signature
      @format_signature ||= self.class.patterns["format_signatures"]&.find do |sig|
        compile_regex(sig["trigger_regex"])&.match?(@text)
      end
    end

    def format_name
      format_signature&.dig("name")
    end

    def invalid?
      name = format_name
      name.present? && name.downcase.include?("invalid") || name.to_s.include?("무효")
    end

    def fields
      return {} if invalid? || format_name.nil?
      result = {}
      (self.class.patterns["field_extractors"] || []).each do |fe|
        next unless fe["applies_to_format"] == format_name
        rx = compile_regex(fe["regex"])
        next unless rx
        m = @text.match(rx)
        next unless m
        result[fe["field"].to_sym] = (m[1] || m[0]).to_s.strip
      end
      result
    end

    def must_comply
      (self.class.patterns["must_comply_patterns"] || []).filter_map do |mc|
        rx = compile_regex(mc["trigger_regex"])
        next unless rx && rx.match?(@text)
        {
          category: mc["category"],
          severity: mc["severity"] || "high",
          what_to_do: mc["what_to_do"],
          example: mc["example"]
        }
      end
    end

    def nice_to_have
      (self.class.patterns["nice_to_have_patterns"] || []).filter_map do |n|
        rx = compile_regex(n["regex"])
        next unless rx && rx.match?(@text)
        {
          type: n["type"],
          what_it_means: n["what_it_means"],
          example: n["example"]
        }
      end
    end

    def summary
      {
        format: format_name,
        invalid: invalid?,
        fields: fields,
        must_count: must_comply.size,
        nice_count: nice_to_have.size,
        critical_count: must_comply.count { |m| m[:severity] == "critical" }
      }
    end

    private

    # "/pattern/imx" 문자열을 Ruby Regexp로 변환.
    # JSON에서 온 정규식은 따옴표 안의 슬래시 표기 (e.g. "/PO NO\\s+(\\d{10})/im")
    def compile_regex(str)
      return nil if str.blank?
      m = str.match(%r{\A/(.+)/([imx]*)\z}m)
      return nil unless m
      flags = 0
      flags |= Regexp::IGNORECASE if m[2].include?("i")
      flags |= Regexp::MULTILINE if m[2].include?("m")
      flags |= Regexp::EXTENDED if m[2].include?("x")
      Regexp.new(m[1], flags)
    rescue RegexpError => e
      Rails.logger.warn("[RfqAuto::FormatMatcher] bad regex #{str}: #{e.message}")
      nil
    end
  end
end
