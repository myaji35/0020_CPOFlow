require "test_helper"

# ISS-358 Wave 4 (T10) — VisionItemExtractor SYSTEM_PROMPT 검증.
# Wave 0에서 추가된 manufacturer/brand/part_no/remarks 4개 키가
# 시스템 프롬프트에 정확히 포함되어 있는지 정합성 검증.
module RfqAuto
  class VisionItemExtractorTest < ActiveSupport::TestCase
    setup { I18n.locale = :ko }

    test "SYSTEM_PROMPT instructs extraction of manufacturer/brand/part_no/remarks" do
      prompt = RfqAuto::VisionItemExtractor::SYSTEM_PROMPT
      assert_match(/manufacturer/i, prompt, "SYSTEM_PROMPT manufacturer 키 누락")
      assert_match(/brand/i, prompt, "SYSTEM_PROMPT brand 키 누락")
      assert_match(/part_no|part\s*no/i, prompt, "SYSTEM_PROMPT part_no 키 누락")
      assert_match(/remarks/i, prompt, "SYSTEM_PROMPT remarks 키 누락")
    end

    test "SYSTEM_PROMPT 의 JSON schema 예시에 4개 키가 모두 들어있다" do
      prompt = RfqAuto::VisionItemExtractor::SYSTEM_PROMPT
      %w[manufacturer brand part_no remarks].each do |key|
        assert prompt.include?("\"#{key}\""), "schema 예시 누락: #{key}"
      end
    end

    test "MODEL ENV override 가능 (claude-sonnet-4-6 기본)" do
      assert_equal "claude-sonnet-4-6", RfqAuto::VisionItemExtractor::MODEL
    end

    test "AnthropicCreditError / VisionUnavailableError 정의됨" do
      assert defined?(RfqAuto::VisionItemExtractor::AnthropicCreditError)
      assert defined?(RfqAuto::VisionItemExtractor::VisionUnavailableError)
      assert RfqAuto::VisionItemExtractor::AnthropicCreditError <= StandardError
    end
  end
end
