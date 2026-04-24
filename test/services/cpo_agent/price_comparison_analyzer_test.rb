# frozen_string_literal: true

require "test_helper"

class CpoAgent::PriceComparisonAnalyzerTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "price_cmp_test@example.com") do |u|
      u.name = "Price Cmp Test"; u.password = "password123"; u.role = :member
    end
    @client = Client.create!(name: "Price Cmp Client", code: "PRC#{SecureRandom.hex(3)}")
  end

  def teardown
    Order.where("title LIKE 'PriceCmp%'").destroy_all
    @client.destroy if Client.exists?(@client.id)
  end

  test "call — supplier 없으면 nil 반환" do
    order = Order.create!(title: "PriceCmp no supplier", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier_id: nil, estimated_value: 1000)
    result = CpoAgent::PriceComparisonAnalyzer.new(order).call
    assert_nil result
  end

  test "call — estimated_value 0이면 nil 반환" do
    order = Order.create!(title: "PriceCmp zero value", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          estimated_value: 0)
    result = CpoAgent::PriceComparisonAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 과거 주문 부족하면 nil 반환" do
    supplier = Supplier.create!(name: "PriceCmp Supplier #{SecureRandom.hex(4)}", code: "PCMS#{SecureRandom.hex(3)}")
    order = Order.create!(title: "PriceCmp single order", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier: supplier, estimated_value: 1000)
    result = CpoAgent::PriceComparisonAnalyzer.new(order).call
    assert_nil result
    order.reload.destroy
    supplier.destroy
  end
end
