# frozen_string_literal: true

require "test_helper"

# ISS-054 Phase C4: ShadowFnDetectorJob — Shadow Mode False Negative 감지
#
# 검증 대상:
#  - would_exclude=true 인 v2 로그 중 order.rfq_status="rfq_triage" 인 건만 FN 카운트
#  - order_id=nil 인 로그는 제외
#  - Order가 아직 rfq_pending 이면 FN 아님
#  - 최소 1건 FN 발견 시 Rails.logger.error 호출
class ShadowFnDetectorJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(
      email:    "iss054_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      name:     "ISS-054 Tester",
      role:     :member
    )
    @tag = "iss054-#{SecureRandom.hex(3)}"
  end

  teardown do
    order_ids = Order.where(user_id: @user.id).pluck(:id)
    ClassificationLog.where(order_id: order_ids).delete_all if order_ids.any?
    ClassificationLog.where("email_message_id LIKE ?", "#{@tag}%").delete_all
    Order.where(user_id: @user.id).destroy_all
    @user.destroy if User.exists?(@user.id)
  end

  def build_order!(rfq_status:)
    Order.create!(
      user:          @user,
      title:         "ISS-054 test order",
      customer_name: "Test Buyer",
      status:        :new_rfq,
      rfq_status:    rfq_status,
      source_type:   :email
    )
  end

  def build_log!(order:, msg_suffix:, would_exclude: true)
    ClassificationLog.create!(
      classifier_version: "v2",
      email_message_id:   "#{@tag}-#{msg_suffix}",
      order_id:           order&.id,
      stage_reached:      1,
      verdict:            "excluded",
      is_rfq:             false,
      confidence:         0.95,
      would_exclude:      would_exclude,
      reason:             "stage1_no_rfq_signal",
      cost_usd:           0.0,
      latency_ms:         10,
      cache_hit:          false,
      model:              "rule-only"
    )
  end

  test "no_logs: classification_logs 비어있으면 suspects=0, fn=0 반환 (테스트 범위 내)" do
    result = ShadowFnDetectorJob.new.perform(window_hours: 24)
    assert_kind_of Hash, result
    assert_equal 0, result[:fn]
    assert_operator result[:suspects], :>=, 0
  end

  test "log_without_order: order_id=nil 인 로그는 suspects 대상에서 제외 → fn=0" do
    build_log!(order: nil, msg_suffix: "nil-order")
    result = ShadowFnDetectorJob.new.perform(window_hours: 24)
    assert_equal 0, result[:fn]
  end

  test "log_with_order_still_pending: Order.rfq_status=rfq_pending → FN 아님" do
    order = build_order!(rfq_status: :rfq_pending)
    build_log!(order: order, msg_suffix: "pending")
    result = ShadowFnDetectorJob.new.perform(window_hours: 24)
    assert_equal 0, result[:fn]
  end

  test "log_with_order_triaged: Order.rfq_status=rfq_triage → FN 1건 + logger.error 호출" do
    order = build_order!(rfq_status: :rfq_triage)
    build_log!(order: order, msg_suffix: "triaged")

    original_logger = Rails.logger
    fake_logger = Class.new do
      attr_accessor :error_called, :last_msg
      def initialize; @error_called = false; end
      def error(msg); @error_called = true; @last_msg = msg; end
      def info(_msg); end
      def warn(_msg); end
      def debug(_msg); end
      def fatal(_msg); end
      def unknown(_msg); end
    end.new
    Rails.logger = fake_logger

    begin
      result = ShadowFnDetectorJob.new.perform(window_hours: 24)
    ensure
      Rails.logger = original_logger
    end

    assert_equal 1, result[:fn], "rfq_triage 로 확정된 order 는 FN 이어야 한다"
    assert fake_logger.error_called, "FN 발견 시 Rails.logger.error 가 호출되어야 한다"
    assert_match(/FN detected/, fake_logger.last_msg.to_s)
  end
end
