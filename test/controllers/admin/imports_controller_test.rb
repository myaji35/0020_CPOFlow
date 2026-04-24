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

  test "show — 존재하는 import_log id 접근" do
    log = ImportLog.create!(status: :pending, import_type: "products", user: @user, filename: "test.xlsx")
    get admin_import_path(log)
    assert_response :success
    log.destroy
  end

  test "show — 존재하지 않는 id는 redirect 또는 404" do
    get admin_import_path(id: 99999999)
    assert_includes [302, 404], response.status
  end

  test "index — 검색 파라미터 적용" do
    get admin_imports_path, params: { q: "products" }
    assert_response :success
  end

  test "index — 페이지네이션" do
    get admin_imports_path, params: { page: 1 }
    assert_response :success
  end

  test "download_errors — error_details 없는 log는 redirect" do
    log = ImportLog.create!(status: :completed, import_type: "products", user: @user, filename: "test.xlsx")
    get download_errors_admin_import_path(log)
    assert_response :redirect
    log.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
