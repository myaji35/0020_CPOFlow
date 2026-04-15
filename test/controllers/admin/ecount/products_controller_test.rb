# frozen_string_literal: true

require "test_helper"

class Admin::Ecount::ProductsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by!(email: "ecount_products_ctrl@example.com") do |u|
      u.name = "Ecount Products Test"; u.password = "password123"; u.role = :admin
    end
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "index — 200 응답" do
    get admin_ecount_products_path
    assert_response :success
  end

  test "index — 검색 파라미터 적용" do
    get admin_ecount_products_path, params: { q: "test_search_term" }
    assert_response :success
  end

  test "index — 페이지 파라미터 적용" do
    get admin_ecount_products_path, params: { page: 1 }
    assert_response :success
  end
end
