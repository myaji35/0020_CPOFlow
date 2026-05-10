require "test_helper"

module Rfp
  class ItemExtractorTest < ActiveSupport::TestCase
    test "build_user_message without format_context falls back to base prompt" do
      ext = ItemExtractor.new
      msg = ext.send(:build_user_message, "본문 내용", nil)
      assert msg.include?("본문 내용")
      assert msg.include?("RFQ/RFP")
      assert_not msg.include?("양식 사전 인식")
    end

    test "build_user_message with format_context injects header + must blocks" do
      ext = ItemExtractor.new
      ctx = {
        format: "NAWAH PO Standard",
        fields: { po_number: "4500020346", buyer_name: "Test Buyer" },
        must_comply: [
          { category: "Z_NPE_CMTR", severity: "critical" },
          { category: "Packaging", severity: "high" }
        ]
      }
      msg = ext.send(:build_user_message, "본문 내용", ctx)
      assert msg.include?("NAWAH PO Standard")
      assert msg.include?("4500020346")
      assert msg.include?("Z_NPE_CMTR")
      assert msg.include?("라인 아이템")
      assert msg.include?("본문 내용")
    end

    test "DEFAULT_MODEL is Haiku 4.5" do
      assert_equal "claude-haiku-4-5-20251001", ItemExtractor::DEFAULT_MODEL
    end

    # ISS-358 Wave 4 (T10) — Wave 0에서 추가된 4개 키가 BASE_SYSTEM_PROMPT에 들어있는지 검증
    test "BASE_SYSTEM_PROMPT 가 manufacturer/brand/part_no/remarks 4개 키를 명시" do
      prompt = ItemExtractor::BASE_SYSTEM_PROMPT
      %w[manufacturer brand part_no remarks].each do |key|
        assert prompt.include?("\"#{key}\""), "BASE_SYSTEM_PROMPT 누락 키: #{key}"
      end
    end

    test "BASE_SYSTEM_PROMPT example 응답에도 4개 키가 들어있다 (1-shot 일관성)" do
      prompt = ItemExtractor::BASE_SYSTEM_PROMPT
      # Example 출력에 새 4개 키가 명시적으로 등장 (null 또는 값) 해야 LLM이 일관성 있게 따라옴
      %w[manufacturer brand part_no remarks].each do |key|
        assert prompt.match?(/"#{key}":/), "1-shot example 출력에 #{key} 미포함"
      end
    end
  end
end
