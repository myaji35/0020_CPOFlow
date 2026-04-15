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

  # ── extract_body (private) ──────────────────────────────
  test "extract_body — nil payload 시 빈 문자열 반환" do
    svc = Gmail::GmailService.allocate
    assert_equal "", svc.send(:extract_body, nil)
  end

  test "extract_body — text/plain payload 처리" do
    body_mock = Struct.new(:data).new(Base64.urlsafe_encode64("Hello plain text"))
    payload = Struct.new(:mime_type, :body, :parts).new("text/plain", body_mock, nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:extract_body, payload)
    assert_equal "Hello plain text", result
  end

  test "extract_body — parts 없고 body.data nil 시 빈 문자열" do
    body_mock = Struct.new(:data).new(nil)
    payload = Struct.new(:mime_type, :body, :parts).new("multipart/mixed", body_mock, nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:extract_body, payload)
    assert_equal "", result
  end

  # ── extract_html_body (private) ──────────────────────────
  test "extract_html_body — nil payload 시 nil 반환" do
    svc = Gmail::GmailService.allocate
    assert_nil svc.send(:extract_html_body, nil)
  end

  test "extract_html_body — text/html payload 처리" do
    html = "<p>Hello HTML</p>"
    body_mock = Struct.new(:data).new(Base64.urlsafe_encode64(html))
    payload = Struct.new(:mime_type, :body, :parts).new("text/html", body_mock, nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:extract_html_body, payload)
    assert_equal html, result
  end

  test "extract_html_body — parts 없고 mime_type 다를 ���우 nil" do
    body_mock = Struct.new(:data).new(nil)
    payload = Struct.new(:mime_type, :body, :parts).new("text/plain", body_mock, nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:extract_html_body, payload)
    assert_nil result
  end

  # ── parse_date (private) ─────────────────────────────────
  test "parse_date — 유효한 날짜 파싱" do
    svc = Gmail::GmailService.allocate
    result = svc.send(:parse_date, "Mon, 14 Apr 2025 10:00:00 +0000")
    assert result.is_a?(Time)
  end

  test "parse_date — 잘못된 날짜 시 현재 시간 반환" do
    svc = Gmail::GmailService.allocate
    result = svc.send(:parse_date, "invalid date string")
    assert result.is_a?(Time)
  end

  # ── find_part_recursive (private) ────────────────────────
  test "find_part_recursive — nil parts 시 nil 반환" do
    svc = Gmail::GmailService.allocate
    result = svc.send(:find_part_recursive, nil, "text/plain")
    assert_nil result
  end

  test "find_part_recursive — 일치하는 part 반환" do
    PartStruct = Struct.new(:mime_type, :body, :parts) unless defined?(PartStruct)
    BodyStruct = Struct.new(:data) unless defined?(BodyStruct)
    part1 = PartStruct.new("text/html", BodyStruct.new("html"), nil)
    part2 = PartStruct.new("text/plain", BodyStruct.new("data"), nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:find_part_recursive, [part1, part2], "text/plain")
    assert_equal part2, result
  end

  test "find_part_recursive — 일치 없으면 nil 반환" do
    PartStruct2 = Struct.new(:mime_type, :body, :parts) unless defined?(PartStruct2)
    BodyStruct2 = Struct.new(:data) unless defined?(BodyStruct2)
    part1 = PartStruct2.new("text/html", BodyStruct2.new(nil), nil)
    svc = Gmail::GmailService.allocate
    result = svc.send(:find_part_recursive, [part1], "text/plain")
    assert_nil result
  end
end
