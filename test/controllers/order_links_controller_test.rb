require "test_helper"

class OrderLinksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "ol@test.com") do |u|
      u.name = "OL"
      u.password = "password123"
      u.role = :member
    end
    login_as(@user)
    @a = Order.create!(user: @user, title: "Alpha Item", customer_name: "C", reference_no: "OL-001", status: :new_rfq)
    @b = Order.create!(user: @user, title: "Beta Item",  customer_name: "C", reference_no: "OL-002", status: :new_rfq)
    @link = OrderLink.create!(
      source: @a, target: @b, relation: "references",
      status: "suggested", confidence: 0.7
    )
  end

  test "PATCH confirm → status: confirmed + remove turbo stream" do
    patch confirm_order_link_path(@link), as: :turbo_stream
    assert_response :success
    assert_equal "confirmed", @link.reload.status
    assert_match(/turbo-stream action="remove"/, response.body)
  end

  test "PATCH reject → status: rejected + remove turbo stream" do
    patch reject_order_link_path(@link), as: :turbo_stream
    assert_response :success
    assert_equal "rejected", @link.reload.status
  end

  test "GET search — title 매칭" do
    get search_order_links_path, params: { q: "Alpha" }
    assert_response :success
    assert_match(/Alpha Item/, response.body)
  end

  test "GET search — 빈 쿼리는 빈 결과" do
    get search_order_links_path, params: { q: "" }
    assert_response :success
    assert_match(/결과 없음/, response.body)
  end

  test "GET new — 수동 추가 모달 200" do
    get new_order_link_path, params: { order_id: @a.id }
    assert_response :success
  end

  test "POST create — 수동 confirmed 링크 생성" do
    c = Order.create!(user: @user, title: "Gamma", customer_name: "C", reference_no: "OL-003", status: :new_rfq)
    before = OrderLink.confirmed.count
    post order_links_path,
         params: { source_id: @a.id, target_type: "Order", target_id: c.id, relation: "references" },
         as: :turbo_stream
    assert_response :success
    assert_operator OrderLink.confirmed.count, :>, before
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
