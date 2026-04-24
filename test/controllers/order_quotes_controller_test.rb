# frozen_string_literal: true

require "test_helper"

class OrderQuotesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "order_quotes_ctrl_test@example.com") do |u|
      u.name = "OrderQuotes Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @supplier = Supplier.create!(name: "Quote Test Supplier")
    @order = Order.create!(title: "Quote Test Order", customer_name: "Cust", user: @user, status: :make_quo)
  end

  def teardown
    @order.reload.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "new order_quote form 200" do
    get new_order_order_quote_path(@order)
    assert_response :success
  end

  test "order_quotes create — 성공" do
    assert_difference("OrderQuote.count", 1) do
      post order_order_quotes_path(@order), params: {
        order_quote: { supplier_id: @supplier.id, unit_price: 100.0, currency: "USD" }
      }
    end
    OrderQuote.order(created_at: :desc).first&.destroy
  end

  test "order_quotes create — unit_price 0이면 실패" do
    assert_no_difference("OrderQuote.count") do
      post order_order_quotes_path(@order), params: {
        order_quote: { supplier_id: @supplier.id, unit_price: 0, currency: "USD" }
      }
    end
  end

  test "order_quotes destroy — 삭제" do
    quote = OrderQuote.create!(order: @order, supplier: @supplier, unit_price: 200.0, currency: "USD")
    assert_difference("OrderQuote.count", -1) do
      delete order_order_quote_path(@order, quote)
    end
  end

  test "order_quotes select — 선택" do
    quote = OrderQuote.create!(order: @order, supplier: @supplier, unit_price: 300.0, currency: "USD")
    patch select_order_order_quote_path(@order, quote)
    assert_response :redirect
    quote.reload
    assert quote.selected
    quote.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
