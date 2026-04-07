# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "dashboard_test@example.com") do |u|
      u.name     = "Dashboard Test User"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)
  end

  test "dashboard index 200 응답" do
    get dashboard_path
    assert_response :success
  end

  test "dashboard index — KPI 섹션 포함" do
    get dashboard_path
    assert_response :success
    # 대시보드에 KPI 카드 렌더링 확인
    assert_match "Dashboard", response.body
  end

  test "dashboard root 경로 200 응답" do
    get root_path
    assert_response :success
  end

  test "로그인 없이 dashboard 접근 시 로그인 페이지로 리다이렉트" do
    delete destroy_user_session_path
    get dashboard_path
    assert_response :redirect
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
