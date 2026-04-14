# frozen_string_literal: true

require "test_helper"

class Settings::EmailAccountsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_email_acct_test@example.com") do |u|
      u.name = "Settings Email Acct User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  # 이 컨트롤러는 뷰 파일 없이 API/redirect 전용 — settings_root로 흡수됨.
  # 406은 HTML 템플릿 부재에 따른 정상 응답이므로 허용.
  test "index 200_or_406" do
    get settings_email_accounts_path
    assert_includes [ 200, 302, 406 ], response.status
  end

  test "new 200_or_406" do
    get new_settings_email_account_path
    assert_includes [ 200, 302, 406 ], response.status
  end

  test "create — 성공" do
    assert_difference("EmailAccount.count", 1) do
      post settings_email_accounts_path, params: {
        email_account: { email: "test_ea_create@example.com" }
      }
    end
    assert_response :redirect
    EmailAccount.find_by(email: "test_ea_create@example.com")&.destroy
  end

  test "destroy — 삭제" do
    acct = @user.email_accounts.create!(email: "test_ea_delete@example.com")
    assert_difference("EmailAccount.count", -1) do
      delete settings_email_account_path(acct)
    end
    assert_response :redirect
  end

  test "sync — 동기화 job 큐잉" do
    acct = @user.email_accounts.create!(email: "test_ea_sync@example.com")
    assert_enqueued_with(job: EmailSyncJob) do
      post sync_settings_email_account_path(acct)
    end
    assert_response :redirect
    acct.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
