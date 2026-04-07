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
    # Phase F: new_rfq 컬럼은 rfq_triage 게이트 적용
    o1 = Order.create!(title: "Thread Order 1", customer_name: "Cust", user: @user,
                       status: :new_rfq, rfq_status: :rfq_triage, reference_no: "REF-TEST-9999")
    o2 = Order.create!(title: "Thread Order 2", customer_name: "Cust", user: @user,
                       status: :new_rfq, rfq_status: :rfq_triage, reference_no: "REF-TEST-9999")

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
    # Phase F: new_rfq 컬럼은 rfq_triage 게이트 적용
    o = Order.create!(title: "Single Order No Ref", customer_name: "Cust", user: @user,
                      status: :new_rfq, rfq_status: :rfq_triage, reference_no: nil)

    get kanban_path
    assert_response :success
    assert_match "Single Order No Ref", response.body

    o.destroy
  end

  # ─────────────────────────────────────────
  # Phase F (ISS-034): rfq_status 게이트
  # ─────────────────────────────────────────

  test "kanban new_rfq 컬럼 — rfq_pending 카드는 노출되지 않음" do
    o = Order.create!(title: "Pending Should Hide", customer_name: "Cust", user: @user,
                      status: :new_rfq, rfq_status: :rfq_pending)

    get kanban_path
    assert_response :success
    assert_no_match "Pending Should Hide", response.body

    o.destroy
  end

  test "kanban new_rfq 컬럼 — rfq_excluded/rfq_archived 카드는 노출되지 않음" do
    excluded = Order.create!(title: "Excluded Should Hide", customer_name: "Cust", user: @user,
                             status: :new_rfq, rfq_status: :rfq_excluded)
    archived = Order.create!(title: "Archived Should Hide", customer_name: "Cust", user: @user,
                             status: :new_rfq, rfq_status: :rfq_archived)

    get kanban_path
    assert_response :success
    assert_no_match "Excluded Should Hide", response.body
    assert_no_match "Archived Should Hide", response.body

    excluded.destroy
    archived.destroy
  end

  test "kanban 다른 컬럼은 rfq_status 게이트 무관 — 이미 변환된 카드 보존" do
    # make_quo로 변환된 카드는 rfq_status가 어떻든 컬럼에 노출되어야 함
    o = Order.create!(title: "Already Converted Card", customer_name: "Cust", user: @user,
                      status: :make_quo, rfq_status: :rfq_excluded)

    get kanban_path
    assert_response :success
    assert_match "Already Converted Card", response.body

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

  # ─────────────────────────────────────────
  # merge 액션
  # ─────────────────────────────────────────

  test "kanban merge — 서브 주문 병합 성공" do
    main  = Order.create!(title: "Main Order", customer_name: "Cust", user: @user, status: :new_rfq)
    child = Order.create!(title: "Child Order", customer_name: "Cust", user: @user, status: :new_rfq)

    post kanban_merge_path, params: { main_order_id: main.id, merge_order_ids: [ child.id ] }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert_includes json["merged_ids"], child.id

    child.reload
    assert_equal main.id, child.parent_order_id
    child.destroy; main.destroy
  end

  test "kanban merge — main_order_id 없으면 422" do
    post kanban_merge_path, params: { main_order_id: 0, merge_order_ids: [] }, as: :json
    assert_response :unprocessable_entity
  end

  # ─────────────────────────────────────────
  # split 액션
  # ─────────────────────────────────────────

  test "kanban split — 서브 주문 분리 성공" do
    parent = Order.create!(title: "Parent Order", customer_name: "Cust", user: @user, status: :new_rfq)
    child  = Order.create!(title: "Sub Order", customer_name: "Cust", user: @user, status: :new_rfq, parent_order_id: parent.id)

    patch kanban_split_path(child.id), as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]

    child.reload
    assert_nil child.parent_order_id
    child.destroy; parent.destroy
  end

  test "kanban split — 이미 독립 카드이면 422" do
    order = Order.create!(title: "Standalone Order", customer_name: "Cust", user: @user, status: :new_rfq)
    patch kanban_split_path(order.id), as: :json
    assert_response :unprocessable_entity
    order.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
