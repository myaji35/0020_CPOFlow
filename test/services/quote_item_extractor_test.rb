# frozen_string_literal: true

require "test_helper"

class QuoteItemExtractorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "qie-#{SecureRandom.hex(4)}@x.com",
                         password: "Pass1234!", name: "QIE")
    @order = Order.create!(reference_no: "QIE-#{SecureRandom.hex(3)}",
                           title: "T", user: @user, customer_name: "CN")
    pdf_bytes = File.binread(Rails.root.join("test/fixtures/files/sample.pdf"))
    @order.attachments.attach(io: StringIO.new(pdf_bytes), filename: "RFQ.pdf",
                              content_type: "application/pdf")
    @attachment = @order.attachments.first
  end

  test "raises AnthropicCreditError on credit issue" do
    extractor = QuoteItemExtractor.new(@attachment)
    extractor.define_singleton_method(:render_pages) { ["base64data"] }
    extractor.define_singleton_method(:call_anthropic) do |_images|
      raise QuoteItemExtractor::AnthropicCreditError, "insufficient"
    end
    assert_raises(QuoteItemExtractor::AnthropicCreditError) { extractor.call }
  end

  test "returns items + cost on success" do
    extractor = QuoteItemExtractor.new(@attachment)
    extractor.define_singleton_method(:render_pages) { ["b64"] }
    extractor.define_singleton_method(:call_anthropic) do |_images|
      [100, 50, [{ "item" => "SPILL TRAY" }]]
    end
    result = extractor.call
    assert_equal 1, result[:items].size
    assert_equal "SPILL TRAY", result[:items].first["item"]
    assert result[:cost_usd] > 0
    assert_equal "claude-sonnet-4-6", result[:llm_model]
    assert_equal 1, result[:page_count]
    assert result[:latency_ms] >= 0
  end

  test "returns empty items when LLM returns none" do
    extractor = QuoteItemExtractor.new(@attachment)
    extractor.define_singleton_method(:render_pages) { ["b64"] }
    extractor.define_singleton_method(:call_anthropic) { |_| [100, 10, []] }
    result = extractor.call
    assert_equal [], result[:items]
  end

  test "returns empty result with no_images reason when no pages rendered" do
    extractor = QuoteItemExtractor.new(@attachment)
    extractor.define_singleton_method(:render_pages) { [] }
    result = extractor.call
    assert_equal [], result[:items]
    assert_equal 0, result[:page_count]
    assert_equal "no_images", result[:reason]
    assert_equal 0.0, result[:cost_usd]
  end

  test "MODEL constant is claude-sonnet-4-6 by default" do
    assert_equal "claude-sonnet-4-6", QuoteItemExtractor::MODEL
  end

  test "default pages_cap is 5" do
    assert_equal 5, QuoteItemExtractor::DEFAULT_PAGES_CAP
  end
end
