# frozen_string_literal: true

require "test_helper"

class CpoAgent::SupplierRiskAnalyzerTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "supplier_risk_test@example.com") do |u|
      u.name = "Supplier Risk Test"; u.password = "password123"; u.role = :member
    end
    @client = Client.create!(name: "Supplier Risk Client", code: "SRC#{SecureRandom.hex(3)}")
  end

  def teardown
    Order.where("title LIKE 'SupplierRisk%'").destroy_all
    @client.destroy if Client.exists?(@client.id)
  end

  test "call — supplier 없으면 nil 반환" do
    order = Order.create!(title: "SupplierRisk no supplier", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier_id: nil)
    result = CpoAgent::SupplierRiskAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 거래 이력 3건 미만이면 nil 반환" do
    supplier = Supplier.create!(name: "SupplierRisk Few #{SecureRandom.hex(4)}", code: "SRFS#{SecureRandom.hex(3)}")
    order = Order.create!(title: "SupplierRisk few orders", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier: supplier)
    result = CpoAgent::SupplierRiskAnalyzer.new(order).call
    assert_nil result
    order.destroy
    supplier.destroy
  end
end
