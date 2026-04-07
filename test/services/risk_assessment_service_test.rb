# frozen_string_literal: true

require "test_helper"

class RiskAssessmentServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "risk_svc_test@example.com") do |u|
      u.name = "Risk Test User"; u.password = "password123"; u.role = :member
    end
  end

  def make_order(status:, due_date:)
    Order.create!(
      title: "Risk Test Order #{SecureRandom.hex(4)}",
      customer_name: "Cust",
      user: @user,
      status: status,
      due_date: due_date
    )
  end

  test "due_date nil이면 score 0, level none" do
    o = Order.create!(title: "No Due", customer_name: "Cust", user: @user, status: :new_rfq, due_date: nil)
    result = RiskAssessmentService.calculate(o)
    assert_equal 0, result[:score]
    assert_equal "none", result[:level]
    o.destroy
  end

  test "get_grn 상태면 score 0, level none" do
    o = make_order(status: :get_grn, due_date: Date.today + 30)
    result = RiskAssessmentService.calculate(o)
    assert_equal 0, result[:score]
    assert_equal "none", result[:level]
    o.destroy
  end

  test "give_up 상태면 score 0, level none" do
    o = make_order(status: :give_up, due_date: Date.today + 30)
    result = RiskAssessmentService.calculate(o)
    assert_equal 0, result[:score]
    assert_equal "none", result[:level]
    o.destroy
  end

  test "이미 납기 지연(due_date 과거) → score 100, level critical" do
    o = make_order(status: :new_rfq, due_date: Date.today - 1)
    result = RiskAssessmentService.calculate(o)
    assert_equal 100, result[:score]
    assert_equal "critical", result[:level]
    o.destroy
  end

  test "납기 여유 충분(31일 이상) → score 10, level low" do
    o = make_order(status: :new_rfq, due_date: Date.today + 60)
    result = RiskAssessmentService.calculate(o)
    assert_equal 10, result[:score]
    assert_equal "low", result[:level]
    o.destroy
  end

  test "납기 7일 이내 → score 75, level high" do
    # problem 단계: min_days_needed = 3(problem) + 0(get_grn) = 3
    # due_date + 5일 → days_left=5 > min_needed=3, days_left<=7 → score 75
    o = make_order(status: :problem, due_date: Date.today + 5)
    result = RiskAssessmentService.calculate(o)
    assert_equal 75, result[:score]
    assert_equal "high", result[:level]
    o.destroy
  end

  test "납기 14일 이내 → score 50, level medium" do
    # problem 단계: min_needed = 3, days_left=10 → 7 < 10 <= 14 → score 50
    o = make_order(status: :problem, due_date: Date.today + 10)
    result = RiskAssessmentService.calculate(o)
    assert_equal 50, result[:score]
    assert_equal "medium", result[:level]
    o.destroy
  end

  test "납기 30일 이내 → score 25, level low" do
    # problem 단계: min_needed = 3, days_left=20 → 14 < 20 <= 30 → score 25
    o = make_order(status: :problem, due_date: Date.today + 20)
    result = RiskAssessmentService.calculate(o)
    assert_equal 25, result[:score]
    assert_equal "low", result[:level]
    o.destroy
  end

  test "batch_update! — active 주문 위험도 업데이트" do
    o = make_order(status: :new_rfq, due_date: Date.today - 2)
    count = RiskAssessmentService.batch_update!
    assert count >= 1
    o.reload
    assert_equal "critical", o.risk_level
    o.destroy
  end

  test "batch_update! — get_grn 주문은 none으로 초기화" do
    o = make_order(status: :get_grn, due_date: Date.today + 10)
    o.update_columns(risk_level: "high", risk_score: 75)
    RiskAssessmentService.batch_update!
    o.reload
    assert_equal "none", o.risk_level
    assert_equal 0, o.risk_score
    o.destroy
  end
end
