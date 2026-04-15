# frozen_string_literal: true

require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "orders_ctrl_test@example.com") do |u|
      u.name     = "Orders Test User"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)
  end

  # ─── index ───────────────────────────────

  test "orders index 200 응답" do
    get orders_path
    assert_response :success
  end

  test "orders index — 주문 목록 표시" do
    order = Order.create!(title: "List Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    get orders_path
    assert_response :success
    assert_match "List Test Order", response.body
    order.destroy
  end

  # ─── show ────────────────────────────────

  test "orders show 200 응답" do
    order = Order.create!(title: "Show Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    get order_path(order)
    assert_response :success
    order.destroy
  end

  # ─── new / create ─────────────────────────

  test "new order form 200 응답" do
    get new_order_path
    assert_response :success
  end

  test "orders create — 성공" do
    assert_difference("Order.count", 1) do
      post orders_path, params: {
        order: {
          title: "Create Test Order",
          customer_name: "Test Customer",
          status: "new_rfq"
        }
      }
    end
    Order.find_by(title: "Create Test Order")&.destroy
  end

  test "orders create — title 없으면 실패" do
    assert_no_difference("Order.count") do
      post orders_path, params: {
        order: { title: "", customer_name: "Test" }
      }
    end
  end

  # ─── edit / update ────────────────────────

  test "edit order form 200 응답" do
    order = Order.create!(title: "Edit Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    get edit_order_path(order)
    assert_response :success
    order.destroy
  end

  test "orders update — title 변경 성공" do
    order = Order.create!(title: "Update Before", customer_name: "Cust", user: @user, status: :new_rfq)
    patch order_path(order), params: { order: { title: "Update After" } }
    order.reload
    assert_equal "Update After", order.title
    order.destroy
  end

  # ─── destroy ─────────────────────────────

  test "orders destroy — 삭제 성공" do
    order = Order.create!(title: "Delete Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    assert_difference("Order.count", -1) do
      delete order_path(order)
    end
  end

  # ─── quick_update ─────────────────────────

  test "quick_update — due_date 변경" do
    order = Order.create!(title: "Quick Update Test", customer_name: "Cust", user: @user, status: :new_rfq)
    due = 7.days.from_now.to_date
    patch quick_update_order_path(order), params: { order: { due_date: due.to_s } }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    order.reload
    assert_equal due, order.due_date
    order.destroy
  end

  # ─── move_status ─────────────────────────
  test "move_status — status 변경 성공" do
    order = Order.create!(title: "Move Status Test", customer_name: "Cust", user: @user, status: :new_rfq)
    patch move_status_order_path(order), params: { status: "make_quo" }
    order.reload
    assert_equal "make_quo", order.status
    order.destroy
  end

  test "move_status — 다른 유효 status로 변경" do
    order = Order.create!(title: "Move Status Bad Test", customer_name: "Cust", user: @user, status: :new_rfq)
    patch move_status_order_path(order), params: { status: "pending_po" }
    order.reload
    assert_equal "pending_po", order.status
    order.destroy
  end

  # ─── attach — 파일 없이 호출 ──────────────
  test "attach — 파일 없으면 alert redirect" do
    order = Order.create!(title: "Attach Test", customer_name: "Cust", user: @user, status: :new_rfq)
    post attach_order_path(order), params: { files: nil }
    assert_response :redirect
    order.destroy
  end

  test "attach — JSON 요청 시 422 반환" do
    order = Order.create!(title: "Attach JSON Test", customer_name: "Cust", user: @user, status: :new_rfq)
    post attach_order_path(order), params: { files: nil }, as: :json
    assert_response :unprocessable_entity
    order.destroy
  end

  # ─── index 필터 ──────────────────────────
  test "orders index — status 필터 적용" do
    get orders_path, params: { status: "new_rfq" }
    assert_response :success
  end

  test "orders index — JSON 응답" do
    get orders_path, as: :json
    assert_includes [200, 406], response.status
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
