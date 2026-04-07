# frozen_string_literal: true

require "test_helper"

class OrgChartControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "orgchart_ctrl_test@example.com") do |u|
      u.name = "OrgChart Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "org_chart index 200" do
    get org_chart_path
    assert_response :success
  end

  test "org_chart index — country 파라미터" do
    get org_chart_path, params: { country: "KR" }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
