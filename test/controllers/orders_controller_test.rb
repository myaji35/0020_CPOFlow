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

  test "orders destroy — 삭제 성공 (manager)" do
    @user.update!(role: :manager)
    order = Order.create!(title: "Delete Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    assert_difference("Order.count", -1) do
      delete order_path(order)
    end
    @user.update!(role: :member)
  end

  test "orders destroy — member는 차단됨 (require_manager!)" do
    order = Order.create!(title: "Delete Blocked", customer_name: "Cust", user: @user, status: :new_rfq)
    assert_no_difference("Order.count") do
      delete order_path(order)
    end
    assert_response :redirect
    order.destroy
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

  # ─── destroy ─────────────────────────────
  test "orders destroy — 삭제 성공 후 kanban redirect (manager)" do
    @user.update!(role: :manager)
    order = Order.create!(title: "Destroy Test", customer_name: "Cust", user: @user, status: :new_rfq)
    delete order_path(order)
    assert_response :redirect
    assert_not Order.exists?(order.id)
    @user.update!(role: :member)
  end

  test "orders destroy — JSON 요청 시 success:true (manager)" do
    @user.update!(role: :manager)
    order = Order.create!(title: "Destroy JSON Test", customer_name: "Cust", user: @user, status: :new_rfq)
    delete order_path(order), as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    @user.update!(role: :member)
  end

  # ─── detach ──────────────────────────────
  test "detach — 존재하지 않는 blob_id는 에러 없이 처리됨" do
    order = Order.create!(title: "Detach Test", customer_name: "Cust", user: @user, status: :new_rfq)
    delete detach_order_path(order, blob_id: 99999999)
    assert_includes [302, 404, 422], response.status
    order.destroy
  end

  # ─── preview_by_ref ───────────────────────
  test "preview_by_ref — ref_no 없으면 에러 없이 처리됨" do
    get preview_by_ref_orders_path, params: { ref_no: "NONEXISTENT_REF_#{SecureRandom.hex(4)}" }
    assert_includes [200, 400, 404], response.status
  end

  # ─── quick_update 추가 케이스 ─────────────
  test "quick_update — rfq_no 변경 성공" do
    order = Order.create!(title: "QU RFQ Test", customer_name: "Cust", user: @user, status: :new_rfq)
    patch quick_update_order_path(order), params: { order: { rfq_no: "RFQ-2026-001" } }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    order.destroy
  end

  # ─── move_status 추가 케이스 ─────────────
  test "move_status — done 상태로 변경" do
    order = Order.create!(title: "Move Done Test", customer_name: "Cust", user: @user, status: :new_rfq)
    patch move_status_order_path(order), params: { status: "done" }
    assert_response :redirect
    order.reload
    assert_equal "done", order.status
    order.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
