# frozen_string_literal: true

require "test_helper"

class Admin::SheetsConfigControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "admin_sheets_test@example.com") do |u|
      u.name = "Admin Sheets User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "update — 유효한 URL로 저장" do
    valid_url = "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms/edit"
    patch admin_sheets_config_path, params: { spreadsheet_url: valid_url }
    assert_response :redirect
  end

  test "update — 잘못된 URL은 alert" do
    patch admin_sheets_config_path, params: { spreadsheet_url: "not-a-valid-url" }
    assert_response :redirect
    assert flash[:alert].present?
  end

  test "clear — 설정 초기화" do
    delete admin_sheets_config_clear_path
    assert_response :redirect
    assert flash[:notice].present?
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
