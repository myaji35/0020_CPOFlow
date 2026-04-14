# frozen_string_literal: true

require "test_helper"

class Settings::MenuPermissionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_menuperm_test@example.com") do |u|
      u.name = "Settings MenuPerm User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "index 200" do
    get settings_menu_permissions_path
    assert_response :success
  end

  test "index — 역할 파라미터" do
    get settings_menu_permissions_path, params: { role: "member" }
    assert_response :success
  end

  test "update_all — 저장 성공" do
    patch settings_update_menu_permissions_path, params: {
      role: "member",
      permissions: {}
    }
    assert_response :redirect
  end

  test "update_all — 잘못된 역할은 redirect with alert" do
    patch settings_update_menu_permissions_path, params: { role: "invalid_role" }
    assert_response :redirect
    assert flash[:alert].present?
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
