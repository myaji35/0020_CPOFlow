# frozen_string_literal: true

require "test_helper"

class Orders::BulkControllerTest < ActionDispatch::IntegrationTest
  def setup
    @manager = User.find_or_create_by(email: "bulk_orders_ctrl_test@example.com") do |u|
      u.name = "Bulk Orders Test Manager"; u.password = "password123"; u.role = :manager
    end
    @manager.update!(role: :manager)
    login_as(@manager)
    @order1 = Order.create!(title: "Bulk Order 1", customer_name: "Cust", user: @manager, status: :new_rfq)
    @order2 = Order.create!(title: "Bulk Order 2", customer_name: "Cust", user: @manager, status: :new_rfq)
  end

  def teardown
    @order1.destroy if Order.exists?(@order1.id)
    @order2.destroy if Order.exists?(@order2.id)
  end

  test "bulk update — status 변경" do
    post orders_bulk_path, params: {
      order_ids: [ @order1.id, @order2.id ],
      action_type: "status",
      status: "make_quo"
    }
    assert_response :redirect
    @order1.reload; @order2.reload
    assert_equal "make_quo", @order1.status
    assert_equal "make_quo", @order2.status
  end

  test "bulk update — 선택 없으면 리다이렉트" do
    post orders_bulk_path, params: {
      order_ids: [],
      action_type: "status",
      status: "make_quo"
    }
    assert_response :redirect
  end

  test "bulk export_csv — CSV 다운로드" do
    get export_csv_orders_bulk_path, params: {
      order_ids: [ @order1.id, @order2.id ]
    }
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.content_type
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
