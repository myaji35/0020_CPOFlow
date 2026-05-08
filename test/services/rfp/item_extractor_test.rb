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
  end
end
