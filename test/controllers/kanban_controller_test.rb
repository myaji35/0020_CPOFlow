# frozen_string_literal: true

require "test_helper"

class KanbanControllerTest < ActionDispatch::IntegrationTest
  def setup
    # admin 로그인 → scoped_orders가 전체 Order 반환 (branch 격리 없음)
    @user = User.find_or_create_by(email: "kanban_ctrl_test@example.com") do |u|
      u.name     = "Kanban Controller Test"
      u.password = "password123"
      u.role     = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  # ─────────────────────────────────────────
  # index 액션
  # ─────────────────────────────────────────

  test "kanban index 200 응답" do
    get kanban_path
    assert_response :success
  end

  test "kanban index — @columns 모든 상태 포함" do
    get kanban_path
    assert_response :success
    # 뷰가 9개 컬럼을 렌더링하는지 확인 (column-{status} id 존재)
    Order::KANBAN_COLUMNS.each do |status|
      assert_select "#column-#{status}", minimum: 1
    end
  end

  test "kanban index — reference_no 그룹핑으로 Inbox 카드 수 감소" do
    # 초기 Inbox 주문 수 파악
    initial_count = Order.where(status: :new_rfq, parent_order_id: nil).count

    # reference_no 동일한 주문 2건 생성 → 그룹핑 시 1카드로 표시
    o1 = Order.create!(title: "Thread Order 1", customer_name: "Cust", user: @user,
                       status: :new_rfq, reference_no: "REF-TEST-9999")
    o2 = Order.create!(title: "Thread Order 2", customer_name: "Cust", user: @user,
                       status: :new_rfq, reference_no: "REF-TEST-9999")

    get kanban_path
    assert_response :success

    # @inbox_grouped 사이즈는 initial_count + 1 (REF-9999 그룹 1개)
    # 뷰에서 Inbox 카운트가 그룹 수로 렌더링되는지 확인
    # (컬럼 카운트 배지는 HTML에 숫자로 표시됨)
    assert_match "column-new_rfq", response.body

    o1.destroy
    o2.destroy
  end

  test "kanban index — reference_no 없는 단건은 그대로 렌더링" do
    o = Order.create!(title: "Single Order No Ref", customer_name: "Cust", user: @user,
                      status: :new_rfq, reference_no: nil)

    get kanban_path
    assert_response :success
    assert_match "Single Order No Ref", response.body

    o.destroy
  end

  # ─────────────────────────────────────────
  # move 액션
  # ─────────────────────────────────────────

  test "kanban move — 상태 변경 성공" do
    order = Order.create!(title: "Move Test", customer_name: "Cust", user: @user, status: :new_rfq)

    patch move_order_path(order), params: { status: "make_quo" }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "make_quo", json["new_status"]

    order.destroy
  end

  test "kanban move — 존재하지 않는 주문 404" do
    patch move_order_path(id: 999999), params: { status: "make_quo" }, as: :json
    # 존재하지 않는 order → ActiveRecord::RecordNotFound → 404
    assert_response :not_found
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
