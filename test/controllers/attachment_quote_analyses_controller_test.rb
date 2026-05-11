# frozen_string_literal: true

require "test_helper"

class AttachmentQuoteAnalysesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ctrl-#{SecureRandom.hex(4)}@x.com",
                        password: "Pass1234!", name: "C", role: "member")
    @order = Order.create!(reference_no: "CT-#{SecureRandom.hex(3)}",
                           title: "T", user: @user, customer_name: "CN")
    @order.attachments.attach(io: StringIO.new("d"), filename: "RFQ.pdf",
                              content_type: "application/pdf")
    @attachment = @order.attachments.first
    login_as(@user)
  end

  teardown do
    @order.reload.attachments.each(&:purge)
    @order.reload.destroy
    @user.reload.destroy
  end

  test "create enqueues job + creates AQA" do
    assert_enqueued_with(job: QuoteAttachmentAnalyzeJob) do
      post attachment_quote_analyses_path,
           params: { attachment_id: @attachment.id }, as: :turbo_stream
    end
    assert_response :success
    assert AttachmentQuoteAnalysis.exists?(active_storage_attachment_id: @attachment.id)
  end

  test "create blocks viewer" do
    @user.update!(role: "viewer")
    post attachment_quote_analyses_path,
         params: { attachment_id: @attachment.id }, as: :turbo_stream
    assert_response :forbidden
  end

  test "reanalyze increments reanalyzed_count + clears error" do
    aqa = AttachmentQuoteAnalysis.create!(
      order: @order, active_storage_attachment_id: @attachment.id,
      status: "failed", error_message: "boom"
    )
    assert_enqueued_with(job: QuoteAttachmentAnalyzeJob) do
      post reanalyze_attachment_quote_analysis_path(aqa), as: :turbo_stream
    end
    aqa.reload
    assert_equal 1, aqa.reanalyzed_count
    assert_equal "pending", aqa.status
    assert_nil aqa.error_message
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "Pass1234!" }
    }
  end
end
