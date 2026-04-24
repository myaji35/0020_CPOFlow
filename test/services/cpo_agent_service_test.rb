# frozen_string_literal: true

require "test_helper"

class CpoAgentServiceTest < ActiveSupport::TestCase
  def setup
    @user     = User.create!(name: "Test User", email: "test_cpo@example.com", password: "password123")
    @supplier = Supplier.create!(name: "Test Supplier")
    @order    = Order.create!(
      title: "Test Order",
      customer_name: "Test Customer",
      user: @user,
      supplier: @supplier,
      status: :new_rfq
    )
  end

  def teardown
    AgentInsight.where(order_id: Order.where(supplier: @supplier).select(:id)).delete_all
    AgentInsight.where(order: @order).delete_all
    Order.where(supplier: @supplier).where.not(id: @order.id).destroy_all
    @order.reload.destroy
    @supplier.destroy
    @user.destroy
  end

  # ─────────────────────────────────────────
  # CpoAgent::Service
  # ─────────────────────────────────────────

  test "Service.analyze 에러 없이 실행" do
    assert_nothing_raised { CpoAgent::Service.analyze(@order) }
  end

  test "Service.analyze 배열 반환" do
    result = CpoAgent::Service.analyze(@order)
    assert_kind_of Array, result
  end

  # ─────────────────────────────────────────
  # PriceComparisonAnalyzer
  # ─────────────────────────────────────────

  test "PriceComparisonAnalyzer: supplier 없으면 nil 반환" do
    order = Order.create!(title: "No Supplier", customer_name: "Test", user: @user, status: :new_rfq)
    result = CpoAgent::PriceComparisonAnalyzer.new(order).call
    assert_nil result
    order.reload.destroy
  end

  test "PriceComparisonAnalyzer: estimated_value 없으면 nil 반환" do
    result = CpoAgent::PriceComparisonAnalyzer.new(@order).call
    assert_nil result  # estimated_value가 nil이면 nil
  end

  test "PriceComparisonAnalyzer: 과거 주문 2건 미만이면 nil 반환" do
    @order.update!(estimated_value: 1000)
    # 과거 주문이 0건이므로 nil 반환
    result = CpoAgent::PriceComparisonAnalyzer.new(@order).call
    assert_nil result
  end

  test "PriceComparisonAnalyzer: 임계값 미만이면 nil 반환" do
    # 평균과 거의 동일한 가격의 과거 주문 생성
    2.times do |i|
      Order.create!(
        title: "Past Order #{i}",
        customer_name: "Cust",
        user: @user,
        supplier: @supplier,
        estimated_value: 1000,
        status: :new_rfq
      )
    end
    @order.update!(estimated_value: 1005)  # 0.5% 차이 → 15% 미만
    result = CpoAgent::PriceComparisonAnalyzer.new(@order).call
    assert_nil result

    Order.where(supplier: @supplier).where.not(id: @order.id).destroy_all
  end

  test "PriceComparisonAnalyzer: 임계값 초과 시 AgentInsight 생성" do
    2.times do |i|
      Order.create!(
        title: "Past Order #{i}",
        customer_name: "Cust",
        user: @user,
        supplier: @supplier,
        estimated_value: 1000,
        status: :new_rfq
      )
    end
    @order.update!(estimated_value: 2000)  # 100% 차이 → warning/alert

    result = CpoAgent::PriceComparisonAnalyzer.new(@order).call
    assert_not_nil result
    assert_equal "price_comparison", result.insight_type
    assert_includes %w[warning alert], result.severity

    Order.where(supplier: @supplier).where.not(id: @order.id).destroy_all
  end

  # ─────────────────────────────────────────
  # SupplierRiskAnalyzer
  # ─────────────────────────────────────────

  test "SupplierRiskAnalyzer: supplier 없으면 nil 반환" do
    order = Order.create!(title: "No Supplier", customer_name: "Test", user: @user, status: :new_rfq)
    result = CpoAgent::SupplierRiskAnalyzer.new(order).call
    assert_nil result
    order.reload.destroy
  end

  test "SupplierRiskAnalyzer: get_grn 주문 3건 미만이면 nil 반환" do
    # get_grn 주문이 없으므로 nil 반환
    result = CpoAgent::SupplierRiskAnalyzer.new(@order).call
    assert_nil result
  end

  test "SupplierRiskAnalyzer: 납기 준수율 계산 로직 동작" do
    # get_grn 상태의 주문 3건 생성
    3.times do |i|
      Order.create!(
        title: "GRN Order #{i}",
        customer_name: "Cust",
        user: @user,
        supplier: @supplier,
        status: :get_grn,
        due_date: 1.month.from_now
      )
    end

    @supplier.update!(credit_grade: "A")
    # get_grn 3건 존재 시 에러 없이 실행됨을 확인
    assert_nothing_raised { CpoAgent::SupplierRiskAnalyzer.new(@order).call }

    @supplier.orders.where.not(id: @order.id).destroy_all
  end

  test "SupplierRiskAnalyzer: credit_grade C 이면 Insight 생성" do
    3.times do |i|
      Order.create!(
        title: "GRN Order #{i}",
        customer_name: "Cust",
        user: @user,
        supplier: @supplier,
        status: :get_grn,
        due_date: 1.month.ago
      )
    end
    @supplier.update!(credit_grade: "C")

    result = CpoAgent::SupplierRiskAnalyzer.new(@order).call
    assert_not_nil result
    assert_equal "supplier_risk", result.insight_type

    @supplier.orders.where.not(id: @order.id).destroy_all
  end

  # ─────────────────────────────────────────
  # DueDateRiskAnalyzer
  # ─────────────────────────────────────────

  test "DueDateRiskAnalyzer: due_date 없으면 nil 반환" do
    @order.update!(due_date: nil)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_nil result
  end

  test "DueDateRiskAnalyzer: get_grn 상태면 nil 반환" do
    # ISS-265: new_rfq → get_grn은 건너뛰기 → force_transition으로 테스트 우회
    @order.force_transition = true
    @order.update!(due_date: 1.day.from_now, status: :get_grn)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_nil result
  end

  test "DueDateRiskAnalyzer: 납기 7일 이상 남으면 nil 반환" do
    @order.update!(due_date: 10.days.from_now, status: :new_rfq)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_nil result
  end

  test "DueDateRiskAnalyzer: D-3 이내이면 alert Insight 생성" do
    @order.update!(due_date: 2.days.from_now, status: :new_rfq)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_not_nil result
    assert_equal "due_date_risk", result.insight_type
    assert_equal "alert", result.severity
  end

  test "DueDateRiskAnalyzer: 납기 초과이면 alert Insight 생성" do
    @order.update!(due_date: 2.days.ago, status: :new_rfq)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_not_nil result
    assert_equal "alert", result.severity
  end

  test "DueDateRiskAnalyzer: D-4~D-7이면 warning Insight 생성" do
    @order.update!(due_date: 5.days.from_now, status: :new_rfq)
    result = CpoAgent::DueDateRiskAnalyzer.new(@order).call
    assert_not_nil result
    assert_equal "warning", result.severity
  end

  # ─────────────────────────────────────────
  # CostSavingAnalyzer
  # ─────────────────────────────────────────

  test "CostSavingAnalyzer: supplier 없으면 nil 반환" do
    order = Order.create!(title: "No Supplier", customer_name: "Test", user: @user, status: :new_rfq)
    result = CpoAgent::CostSavingAnalyzer.new(order).call
    assert_nil result
    order.reload.destroy
  end

  test "CostSavingAnalyzer: estimated_value 없으면 nil 반환" do
    result = CpoAgent::CostSavingAnalyzer.new(@order).call
    assert_nil result
  end

  test "CostSavingAnalyzer: 저렴한 대안 없으면 nil 반환" do
    @order.update!(estimated_value: 100, title: "UniqueProduct99999")
    result = CpoAgent::CostSavingAnalyzer.new(@order).call
    assert_nil result
  end
end
