# frozen_string_literal: true

require "test_helper"

class Settings::AgentTrustControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_agent_trust_test@example.com") do |u|
      u.name = "Settings Agent Trust User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "toggle — 성공 redirect" do
    patch settings_agent_trust_toggle_path(insight_type: "email_classification")
    assert_response :redirect
  end

  test "toggle — 두번 호출하면 토글됨" do
    patch settings_agent_trust_toggle_path(insight_type: "rfq_auto")
    level = AgentTrustLevel.find_by(user: @user, insight_type: "rfq_auto")
    first_value = level.auto_mode

    patch settings_agent_trust_toggle_path(insight_type: "rfq_auto")
    level.reload
    assert_not_equal first_value, level.auto_mode
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
