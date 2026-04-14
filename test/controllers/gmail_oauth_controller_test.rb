# frozen_string_literal: true

require "test_helper"

class GmailOauthControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "gmail_oauth_ctrl_test@example.com") do |u|
      u.name = "Gmail OAuth Ctrl User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "callback — error 파라미터 있으면 settings로 redirect" do
    get gmail_oauth_callback_path, params: { error: "access_denied" }
    assert_response :redirect
    assert_redirected_to settings_root_path
    assert flash[:alert].present?
  end

  test "callback — code 없으면 settings로 redirect" do
    get gmail_oauth_callback_path
    assert_response :redirect
    assert_redirected_to settings_root_path
    assert flash[:alert].present?
  end

  test "disconnect — 존재하지 않는 계정 접근 시 redirect" do
    delete gmail_oauth_disconnect_path(id: 999999)
    assert_response :redirect
    assert_redirected_to settings_root_path
    assert flash[:alert].present?
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
