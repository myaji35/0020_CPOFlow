# frozen_string_literal: true

require "test_helper"

class QuoteAttachmentAnalyzeJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "jb-#{SecureRandom.hex(4)}@x.com",
                         password: "Pass1234!", name: "JB")
    @order = Order.create!(reference_no: "JB-#{SecureRandom.hex(3)}",
                           title: "T", user: @user, customer_name: "CN")
    @order.attachments.attach(io: StringIO.new("d"), filename: "RFQ.pdf",
                              content_type: "application/pdf")
    @aqa = AttachmentQuoteAnalysis.create!(
      order: @order,
      active_storage_attachment_id: @order.attachments.first.id
    )
  end

  test "marks completed and seeds items on success" do
    result = {
      items: [{ "item" => "SPILL TRAY", "description" => "129x119",
                "model_part_no" => "5004-BK", "manufacturer_brand" => "ENPAC",
                "unit" => "EA", "qty" => "16", "remarks" => "" }],
      cost_usd: 0.02, llm_model: "claude-sonnet-4-6",
      page_count: 1, latency_ms: 100
    }
    with_extractor_result(result) do
      QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    end

    @aqa.reload
    assert_equal "completed", @aqa.status
    assert_equal true, @aqa.is_quote_doc
    assert_equal 1, @order.quote_items.count
    assert_equal "SPILL TRAY", @order.quote_items.first.item
    assert_equal 16, @order.quote_items.first.qty.to_i
  end

  test "marks failed on AnthropicCreditError" do
    with_extractor_error(QuoteItemExtractor::AnthropicCreditError, "insufficient") do
      QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    end

    @aqa.reload
    assert_equal "failed", @aqa.status
    assert_match(/insufficient/, @aqa.error_message)
  end

  test "completed but is_quote_doc=false on empty items" do
    result = { items: [], cost_usd: 0.01, llm_model: "claude-sonnet-4-6",
               page_count: 1, latency_ms: 50 }
    with_extractor_result(result) do
      QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    end

    @aqa.reload
    assert_equal "completed", @aqa.status
    assert_equal false, @aqa.is_quote_doc
    assert_equal 0, @order.quote_items.count
  end

  test "marks failed on ExtractionError" do
    with_extractor_error(QuoteItemExtractor::ExtractionError, "pdftoppm failed") do
      QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    end

    @aqa.reload
    assert_equal "failed", @aqa.status
    assert_match(/pdftoppm/, @aqa.error_message)
  end

  test "appends rows to existing quote_items (preserves prior rows)" do
    OrderQuoteItem.create!(order: @order, row_no: 1, item: "EXISTING", user_edited: true)
    result = { items: [{ "item" => "NEW", "qty" => "5" }],
               cost_usd: 0.01, llm_model: "claude-sonnet-4-6",
               page_count: 1, latency_ms: 50 }
    with_extractor_result(result) do
      QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    end

    items = @order.quote_items.ordered
    assert_equal 2, items.count
    assert_equal "EXISTING", items[0].item
    assert_equal "NEW", items[1].item
    assert_equal 2, items[1].row_no
  end

  private

  # QuoteItemExtractor.new(...)를 가로채 call 시 result 반환하도록 패치
  def with_extractor_result(result)
    orig = QuoteItemExtractor.instance_method(:call)
    QuoteItemExtractor.define_method(:call) { result }
    yield
  ensure
    QuoteItemExtractor.define_method(:call, orig)
  end

  # QuoteItemExtractor.new(...)를 가로채 call 시 예외 발생하도록 패치
  def with_extractor_error(error_class, message)
    orig = QuoteItemExtractor.instance_method(:call)
    QuoteItemExtractor.define_method(:call) { raise error_class, message }
    yield
  ensure
    QuoteItemExtractor.define_method(:call, orig)
  end
end
