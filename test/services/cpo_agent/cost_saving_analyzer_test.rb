# frozen_string_literal: true

require "test_helper"

class CpoAgent::CostSavingAnalyzerTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "cost_saving_test@example.com") do |u|
      u.name = "Cost Saving Test"; u.password = "password123"; u.role = :member
    end
    @client = Client.create!(name: "Cost Saving Client", code: "CSC#{SecureRandom.hex(3)}")
  end

  def teardown
    Order.where("title LIKE 'CostSaving%'").destroy_all
    @client.destroy if Client.exists?(@client.id)
  end

  test "call — supplier 없으면 nil 반환" do
    order = Order.create!(title: "CostSaving no supplier", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier_id: nil, estimated_value: 0)
    result = CpoAgent::CostSavingAnalyzer.new(order).call
    assert_nil result
  end

  test "call — estimated_value 0이면 nil 반환" do
    order = Order.create!(title: "CostSaving zero", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          estimated_value: 0)
    result = CpoAgent::CostSavingAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 대체 견적 없으면 nil 반환" do
    supplier = Supplier.create!(name: "CostSaving Supplier #{SecureRandom.hex(4)}", code: "CSMS#{SecureRandom.hex(3)}")
    order = Order.create!(title: "CostSaving no quotes", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          supplier: supplier, estimated_value: 5000)
    result = CpoAgent::CostSavingAnalyzer.new(order).call
    assert_nil result
    order.reload.destroy
    supplier.destroy
  end
end
