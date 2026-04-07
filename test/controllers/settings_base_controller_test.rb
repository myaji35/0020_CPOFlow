# frozen_string_literal: true

require "test_helper"

class Settings::BaseControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_base_test@example.com") do |u|
      u.name = "Settings Base Test"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "settings index 200" do
    get settings_root_path
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
