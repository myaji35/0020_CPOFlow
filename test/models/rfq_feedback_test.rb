# frozen_string_literal: true

require "test_helper"

class RfqFeedbackTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "rfq_fb_test@example.com") do |u|
      u.name = "RfqFeedback Test User"; u.password = "password123"; u.role = :member
    end
    @order = Order.create!(title: "RFQ Feedback Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
  end

  test "verdict 유효 값(confirmed) 허용" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "confirmed")
    assert f.valid?
  end

  test "verdict 유효 값(rejected) 허용" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "rejected")
    assert f.valid?
  end

  test "verdict 유효 값(reverted) 허용" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "reverted")
    assert f.valid?
  end

  test "verdict 잘못된 값 거부" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "unknown")
    assert_not f.valid?
  end

  test "ai_score 범위 초과 시 유효하지 않음" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "confirmed", ai_score: 1.5)
    assert_not f.valid?
  end

  test "ai_score nil 허용" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "confirmed", ai_score: nil)
    assert f.valid?
  end

  test "ai_correct? — AI RFQ 판정, 사용자 confirmed → true" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "confirmed", ai_score: 0.8)
    assert_equal true, f.ai_correct?
  end

  test "ai_correct? — AI RFQ 판정, 사용자 rejected → false" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "rejected", ai_score: 0.8)
    assert_equal false, f.ai_correct?
  end

  test "ai_correct? — ai_score nil이면 nil 반환" do
    f = RfqFeedback.new(order: @order, user: @user, verdict: "confirmed", ai_score: nil)
    assert_nil f.ai_correct?
  end

  test "confirmed scope" do
    f = RfqFeedback.create!(order: @order, user: @user, verdict: "confirmed")
    assert_includes RfqFeedback.confirmed, f
    f.destroy
  end

  test "rejected scope" do
    f = RfqFeedback.create!(order: @order, user: @user, verdict: "rejected")
    assert_includes RfqFeedback.rejected, f
    f.destroy
  end
end
