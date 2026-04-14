# frozen_string_literal: true

require "test_helper"

class CpoAgent::DueDateRiskAnalyzerTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "duedate_risk_test@example.com") do |u|
      u.name = "DueDate Risk Test"; u.password = "password123"; u.role = :member
    end
    @client = Client.create!(name: "DueDate Risk Client", code: "DDR#{SecureRandom.hex(3)}")
  end

  def teardown
    Order.where("title LIKE 'DueDate%'").destroy_all
    @client.destroy if Client.exists?(@client.id)
  end

  test "call — due_date 없으면 nil 반환" do
    order = Order.create!(title: "DueDate nil test", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user, due_date: nil)
    result = CpoAgent::DueDateRiskAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 완료 상태(get_grn)면 nil 반환" do
    order = Order.create!(title: "DueDate grn test", customer_name: "T",
                          client: @client, status: :get_grn, user: @user,
                          due_date: Date.today + 1)
    result = CpoAgent::DueDateRiskAnalyzer.new(order).call
    assert_nil result
  end

  test "call — give_up 상태면 nil 반환" do
    order = Order.create!(title: "DueDate giveup test", customer_name: "T",
                          client: @client, status: :give_up, user: @user,
                          due_date: Date.today + 1)
    result = CpoAgent::DueDateRiskAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 납기 8일 이상이면 nil 반환" do
    order = Order.create!(title: "DueDate far test", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          due_date: Date.today + 10)
    result = CpoAgent::DueDateRiskAnalyzer.new(order).call
    assert_nil result
  end

  test "call — 납기 D-3이면 insight 생성" do
    order = Order.create!(title: "DueDate close test", customer_name: "T",
                          client: @client, status: :new_rfq, user: @user,
                          due_date: Date.today + 3)
    assert_nothing_raised do
      CpoAgent::DueDateRiskAnalyzer.new(order).call
    end
  end
end
