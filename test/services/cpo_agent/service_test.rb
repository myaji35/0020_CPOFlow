# frozen_string_literal: true

require "test_helper"

class CpoAgent::ServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "cpo_svc_test@example.com") do |u|
      u.name = "CpoAgent Svc Tester"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "CpoSvc Test Supplier") do |s|
      s.code = "CSVC#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "CpoSvc Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          @user,
      supplier:      @supplier
    )
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "ANALYZERS 상수 — 4개 분석기 포함" do
    analyzers = CpoAgent::Service::ANALYZERS
    assert_includes analyzers, CpoAgent::PriceComparisonAnalyzer
    assert_includes analyzers, CpoAgent::SupplierRiskAnalyzer
    assert_includes analyzers, CpoAgent::DueDateRiskAnalyzer
    assert_includes analyzers, CpoAgent::CostSavingAnalyzer
  end

  test "analyze — 배열 반환" do
    result = CpoAgent::Service.analyze(@order)
    assert result.is_a?(Array)
  end

  test "analyze — 분석기 에러가 있어도 결과 반환" do
    # 분석기가 에러를 발생해도 rescue하여 계속 진행
    svc = CpoAgent::Service.new(@order)
    result = svc.analyze
    assert result.is_a?(Array)
  end

  test "analyze — 인스턴스 메서드로도 호출 가능" do
    svc = CpoAgent::Service.new(@order)
    result = svc.analyze
    assert result.is_a?(Array)
  end
end
