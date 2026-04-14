# frozen_string_literal: true

require "test_helper"

class Admin::ImportsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "admin_imports_test@example.com") do |u|
      u.name = "Admin Imports User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
  end

  test "index 200" do
    get admin_imports_path
    assert_response :success
  end

  test "new 200" do
    get new_admin_import_path
    assert_response :success
  end

  test "create — 파일 없으면 redirect with alert" do
    post admin_imports_path, params: { import_log: { import_type: "products", import_file: nil } }
    assert_response :redirect
  end

  test "create — 유형 없으면 redirect with alert" do
    post admin_imports_path, params: { import_log: { import_type: "unknown", import_file: nil } }
    assert_response :redirect
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
