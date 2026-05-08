# frozen_string_literal: true

# LAB / RFQ Auto — 양식별 정규식 패턴 매칭 (Phase 2-A/B)
#
# config/rfq_auto/*_patterns.json 의 모든 패턴 라이브러리를 자동 머지해 로드.
# 새 양식 추가 시 새 *_patterns.json 파일만 떨어뜨리면 즉시 활성화.
#
# Sonnet 호출 전 1차 추출 — 정규식만으로 NAWAH/ENEC 82%, BMT 수신 양식 55% 커버.
#
# 사용:
#   matcher = RfqAuto::FormatMatcher.new(text)
#   matcher.format_name         # => "NAWAH PO Standard" or "Kent Supplier Portal..." or nil
#   matcher.fields              # => { po_number: "4500020346", po_date: "13 Apr 2026", ... }
#   matcher.must_comply         # => [{category:, severity:, what_to_do:, example:}, ...]
#   matcher.nice_to_have        # => [{type:, what_it_means:, example:}, ...]
#   matcher.invalid?            # => true (Ariba 로그인 페이지 같은 무효 문서)
module RfqAuto
  class FormatMatcher
    PATTERNS_DIR = Rails.root.join("config/rfq_auto")

    class << self
      def patterns
        @patterns ||= load_patterns
      end

      def reload!
        @patterns = load_patterns
      end

      private

      # 디렉터리 안 모든 *_patterns.json 을 머지. 키별 배열 concat.
      def load_patterns
        merged = { "format_signatures" => [], "field_extractors" => [],
                   "must_comply_patterns" => [], "nice_to_have_patterns" => [] }
        return merged unless Dir.exist?(PATTERNS_DIR)

        Dir.glob(PATTERNS_DIR.join("*_patterns.json")).sort.each do |path|
          begin
            data = JSON.parse(File.read(path))
            merged.each_key do |k|
              merged[k].concat(data[k]) if data[k].is_a?(Array)
            end
          rescue JSON::ParserError => e
            Rails.logger.warn("[RfqAuto::FormatMatcher] #{path} parse failed: #{e.message}")
          end
        end
        merged
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
