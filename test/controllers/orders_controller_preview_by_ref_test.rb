require "test_helper"

class OrdersControllerPreviewByRefTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "pbr@test.com") do |u|
      u.name = "PBR"
      u.password = "password123"
      u.role = :member
    end
    login_as(@user)
    @order = Order.create!(
      user: @user, title: "Pre Test",
      customer_name: "C", reference_no: "PBR-2026-0001",
      status: :new_rfq
    )
    Rails.cache.clear
  end

  test "preview_by_ref 200 + 응답에 ref 포함" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
    assert_match(/PBR-2026-0001/, response.body)
    assert_match(/Pre Test/, response.body)
  end

  test "ref 비어있으면 400" do
    get preview_by_ref_orders_path, params: { ref: "" }
    assert_response :bad_request
  end

  test "캐시 hit — 두 번째 요청도 200 + 동일 응답" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    first_body = response.body
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
    assert_equal first_body, response.body
  end

  test "존재하지 않는 ref → 데이터 없음" do
    get preview_by_ref_orders_path, params: { ref: "NONEXIST-9999" }
    assert_response :success
    assert_match(/데이터 없음/, response.body)
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
