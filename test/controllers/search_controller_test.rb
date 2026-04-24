# frozen_string_literal: true

require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "search_ctrl_test@example.com") do |u|
      u.name = "Search Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "search 1자 미만은 빈 배열 반환" do
    get search_path, params: { q: "a" }, as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "search 2자 이상 — JSON 반환" do
    get search_path, params: { q: "te" }, as: :json
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)
  end

  test "search — Order 검색 결과 포함" do
    order = Order.create!(title: "SearchTest Order XYZ", customer_name: "Cust", user: @user, status: :new_rfq)
    get search_path, params: { q: "SearchTest" }, as: :json
    assert_response :success
    results = JSON.parse(response.body)
    types = results.map { |r| r["type"] }
    assert_includes types, "order"
    order.reload.destroy
  end

  test "search — Client 검색 결과 포함" do
    client = Client.create!(name: "SearchTestClient Corp", code: "CLI-SRCH-#{SecureRandom.hex(4)}", country: "KR")
    get search_path, params: { q: "SearchTestClient" }, as: :json
    assert_response :success
    results = JSON.parse(response.body)
    types = results.map { |r| r["type"] }
    assert_includes types, "client"
    client.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
