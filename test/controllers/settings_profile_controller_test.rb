# frozen_string_literal: true

require "test_helper"

class Settings::ProfileControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_profile_test@example.com") do |u|
      u.name = "Settings Profile User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "profile update — name 변경" do
    patch settings_profile_path, params: { user: { name: "Updated Profile Name" } }
    assert_response :redirect
    @user.reload
    assert_equal "Updated Profile Name", @user.name
    # 원복
    @user.update!(name: "Settings Profile User")
  end

  test "profile update_locale — 유효한 locale 변경" do
    patch settings_update_locale_path, params: { locale: "en" }
    assert_response :redirect
    @user.reload
  end

  test "profile update_theme — 유효한 theme 변경" do
    patch settings_update_theme_path, params: { theme: "dark" }
    assert_response :redirect
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
