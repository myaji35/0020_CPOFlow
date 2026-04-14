# frozen_string_literal: true

require "test_helper"

class Settings::NotificationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_notif_ctrl_test@example.com") do |u|
      u.name = "Settings Notif Ctrl User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "update — Webhook URL 저장" do
    patch settings_notifications_path, params: { google_chat_webhook_url: "https://chat.example.com/webhook" }
    assert_response :redirect
    assert flash[:notice].present?
  end

  test "test — URL 없으면 redirect with alert" do
    AppSetting.set("google_chat_webhook_url", "")
    post settings_test_notifications_path
    assert_response :redirect
    assert flash[:alert].present?
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
