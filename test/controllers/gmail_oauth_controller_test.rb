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

  # ISS-344 (B): disconnect 시 모든 토큰 + scope 완전 정리 (Lockbox 컬럼은 raw write)
  test "ISS-344 (B): disconnect는 connected/expires/scope 모두 정리" do
    account = EmailAccount.create!(
      email: "iss344b@example.com", user: @user, connected: true,
      token_expires_at: 1.hour.from_now, oauth_scope: "https://www.googleapis.com/auth/gmail.readonly"
    )
    delete gmail_oauth_disconnect_path(account)
    account.reload
    refute account.connected, "connected가 false여야 함"
    assert_nil account.token_expires_at, "token_expires_at가 nil이어야 함"
    assert_nil account.oauth_scope, "oauth_scope가 nil이어야 함"
  end

  # ISS-344 (C): user별 분리 — 같은 email을 두 user가 각자 보유
  test "ISS-344 (C): 같은 email을 두 user가 각자 EmailAccount로 보유 가능" do
    other = User.find_or_create_by(email: "iss344c_other@example.com") do |u|
      u.name = "Other User"; u.password = "password123"; u.role = :member
    end
    EmailAccount.create!(email: "shared@gmail.com", user: @user, connected: true)
    account_b = EmailAccount.new(email: "shared@gmail.com", user: other, connected: true)
    assert account_b.valid?, "다른 user의 same email 가능: #{account_b.errors.full_messages}"
    assert account_b.save
    assert_equal 2, EmailAccount.where(email: "shared@gmail.com").count
  end

  # ISS-344 (C): user a가 user b 소유 계정을 disconnect 못함
  test "ISS-344 (C): 다른 user 소유 계정은 disconnect 차단 (find scope)" do
    other = User.find_or_create_by(email: "iss344c_owner@example.com") do |u|
      u.name = "Owner"; u.password = "password123"; u.role = :member
    end
    account_b = EmailAccount.create!(email: "owned-by-other@gmail.com", user: other, connected: true)
    delete gmail_oauth_disconnect_path(account_b)
    account_b.reload
    assert account_b.connected, "다른 user 계정은 disconnect 안 되어야 함"
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
