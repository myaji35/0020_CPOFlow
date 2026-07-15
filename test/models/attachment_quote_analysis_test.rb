require "test_helper"

class AttachmentQuoteAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "aqa-#{SecureRandom.hex(4)}@example.com",
      password: "Pass1234!", name: "AQA"
    )
    @order = Order.create!(
      reference_no: "AQA-#{SecureRandom.hex(3)}",
      title: "AQA 테스트",
      user: @user,
      customer_name: "AQA Customer"
    )
    @order.attachments.attach(
      io: StringIO.new("dummy"), filename: "RFQ-001.pdf", content_type: "application/pdf"
    )
    @attachment = @order.attachments.first
  end

  test "STATUSES whitelist" do
    assert_equal %w[pending running completed failed not_quote], AttachmentQuoteAnalysis::STATUSES
  end

  test "creates with order + attachment" do
    aqa = AttachmentQuoteAnalysis.create!(
      order: @order, active_storage_attachment_id: @attachment.id
    )
    assert_equal "pending", aqa.status
    assert_equal 0, aqa.reanalyzed_count
    assert_equal false, aqa.is_quote_doc
  end

  test "items returns parsed array" do
    aqa = AttachmentQuoteAnalysis.create!(
      order: @order, active_storage_attachment_id: @attachment.id,
      items_json: '[{"item":"X"}]'
    )
    assert_equal [ { "item" => "X" } ], aqa.items
  end

  test "items returns [] when items_json blank or invalid" do
    aqa = AttachmentQuoteAnalysis.new(
      order: @order, active_storage_attachment_id: @attachment.id
    )
    assert_equal [], aqa.items
    aqa.items_json = "{not json"
    assert_equal [], aqa.items
  end

  test "items returns [] when items_json is a hash not array" do
    aqa = AttachmentQuoteAnalysis.new(
      order: @order, active_storage_attachment_id: @attachment.id,
      items_json: '{"items":[]}'
    )
    assert_equal [], aqa.items
  end

  test "unique attachment_id" do
    AttachmentQuoteAnalysis.create!(
      order: @order, active_storage_attachment_id: @attachment.id
    )
    dup = AttachmentQuoteAnalysis.new(
      order: @order, active_storage_attachment_id: @attachment.id
    )
    assert_not dup.valid?
  end

  test "status whitelist enforced" do
    aqa = AttachmentQuoteAnalysis.new(
      order: @order, active_storage_attachment_id: @attachment.id, status: "wat"
    )
    assert_not aqa.valid?
  end

  test "status query methods" do
    aqa = AttachmentQuoteAnalysis.new(status: "running")
    assert aqa.running?
    aqa.status = "completed"
    assert aqa.completed?
    aqa.status = "failed"
    assert aqa.failed?
  end
end
