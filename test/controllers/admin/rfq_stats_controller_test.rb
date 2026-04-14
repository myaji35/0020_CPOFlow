# frozen_string_literal: true

require "test_helper"

class Admin::RfqStatsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "admin_rfq_stats_test@example.com") do |u|
      u.name = "Admin RFQ Stats User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
  end

  test "index HTML 200" do
    get admin_rfq_stats_path
    assert_response :success
  end

  test "index JSON 200" do
    get admin_rfq_stats_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Hash)
  end

  test "index — window 파라미터" do
    get admin_rfq_stats_path, params: { window: 30 }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
