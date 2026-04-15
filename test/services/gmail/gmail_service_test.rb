# frozen_string_literal: true

require "test_helper"

class Gmail::GmailServiceTest < ActiveSupport::TestCase
  def setup
    @user    = User.find_or_create_by!(email: "gmail_svc_test@example.com") do |u|
      u.name = "Gmail Svc Test"; u.password = "password123"; u.role = :member
    end
    @account = @user.email_accounts.find_or_create_by!(email: "gmail_test@example.com")
  end

  def teardown
    EmailAccount.where(user: @user, email: "gmail_test@example.com").destroy_all
  end

  test "SCOPES 상수 정의됨" do
    assert Gmail::GmailService::SCOPES.present?
  end

  test "parse_message — nil 반환" do
    svc = Gmail::GmailService.allocate
    assert_nil svc.parse_message(nil)
  end

  test "parse_message — 빈 payload msg 처리" do
    # Google::Apis::GmailV1::Message 구조와 비슷한 mock 객체 생성
    msg = Struct.new(:id, :thread_id, :snippet, :label_ids, :payload).new(
      "msg123", "thread456", "Test snippet", ["UNREAD"], nil
    )
    svc    = Gmail::GmailService.allocate
    result = svc.parse_message(msg)
    assert_equal "msg123", result[:id]
    assert_equal "thread456", result[:thread_id]
    assert_equal "(no subject)", result[:subject]
    assert_equal "Test snippet", result[:snippet]
    assert result[:unread]
  end

  test "parse_message — labels 없을 때 unread false" do
    msg = Struct.new(:id, :thread_id, :snippet, :label_ids, :payload).new(
      "msg789", "thread000", "Snippet", nil, nil
    )
    svc    = Gmail::GmailService.allocate
    result = svc.parse_message(msg)
    assert_not result[:unread]
    assert_equal [], result[:labels]
  end
end
