# frozen_string_literal: true

require "test_helper"

class EcountApi::SlipCreateServiceTest < ActiveSupport::TestCase
  def setup
    @supplier = Supplier.find_or_create_by!(name: "Slip Test Supplier") do |s|
      s.code = "SLIPSUPP#{SecureRandom.hex(2)}"
    end
    @user = User.find_or_create_by!(email: "slip_svc_test@example.com") do |u|
      u.name = "Slip Svc Tester"; u.password = "password123"; u.role = :member
    end
    @order = Order.create!(
      title:         "Slip Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      estimated_value: 1000.0,
      item_name:     "Test Item",
      supplier:      @supplier,
      user:          @user
    )
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "SlipCreateService < BaseService" do
    svc = EcountApi::SlipCreateService.new(@order)
    assert EcountApi::SlipCreateService.ancestors.include?(EcountApi::BaseService)
  end

  test "create! — ecount_slip_no 이미 있을 때 스킵" do
    @order.update_columns(ecount_slip_no: "EXISTING_SLIP_123")
    svc    = EcountApi::SlipCreateService.new(@order)
    result = svc.create!
    assert result[:ok]
    assert result[:skipped]
    assert_equal "EXISTING_SLIP_123", result[:slip_no]
  end

  test "build_payload — 기본 구조 포함" do
    svc     = EcountApi::SlipCreateService.new(@order)
    payload = svc.send(:build_payload, "test-session-id")
    assert_equal "test-session-id", payload["SESSION_ID"]
    assert payload["SLIP_DATA"].is_a?(Array)
    assert_equal 1, payload["SLIP_DATA"].size
    slip = payload["SLIP_DATA"].first
    assert_equal @order.estimated_value.to_f, slip["PRICE"]
  end

  test "resolve_customer_code — client 없을 때 customer_name 사용" do
    svc  = EcountApi::SlipCreateService.new(@order)
    code = svc.send(:resolve_customer_code)
    # @order에 client 없으므로 customer_name 반환 (nil → "")
    assert code.is_a?(String)
  end

  test "handle_failure — ok: false, error 키 포함" do
    svc    = EcountApi::SlipCreateService.new(@order)
    result = svc.send(:handle_failure, StandardError.new("테스트 오류"))
    assert_not result[:ok]
    assert_equal "테스트 오류", result[:error]
  end
end
