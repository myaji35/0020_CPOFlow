# frozen_string_literal: true

require "test_helper"

class Gmail::RfqDetectorServiceTest < ActiveSupport::TestCase
  def rfq_email(overrides = {})
    {
      subject: "RFQ - 자재 견적 요청",
      body: "안녕하세요. 견적서를 요청드립니다. 납기: 2026-12-31. unit price와 단가표 보내주세요.",
      from: "buyer@client.com"
    }.merge(overrides)
  end

  def non_rfq_email(overrides = {})
    {
      subject: "Invoice Notification - Payment Received",
      body: "Your payment has been received. Thank you.",
      from: "noreply@sendgrid.net"
    }.merge(overrides)
  end

  # keyword_detect 단독 테스트 (LLM 미호출)
  test "keyword_detect — RFQ 키워드 있으면 is_rfq true" do
    service = Gmail::RfqDetectorService.new(rfq_email)
    result = service.keyword_detect
    assert result[:is_rfq]
    assert result[:score] > 0
  end

  test "keyword_detect — 비RFQ 이메일은 score 낮음" do
    service = Gmail::RfqDetectorService.new(non_rfq_email)
    result = service.keyword_detect
    assert result[:score] < 30
  end

  test "keyword_detect — subject_matches에 매칭 키워드 포함" do
    service = Gmail::RfqDetectorService.new(rfq_email(subject: "rfq request for quotation"))
    result = service.keyword_detect
    assert result[:subject_matches].any?
  end

  test "keyword_detect — 자사 도메인 발신자는 자동 제외" do
    service = Gmail::RfqDetectorService.new(rfq_email(from: "me@ddtl.co.kr"))
    result = service.detect
    assert_equal false, result[:is_rfq]
    assert_equal :excluded, result[:rfq_verdict]
  end

  test "keyword_detect — excluded 발신 도메인은 자동 제외" do
    service = Gmail::RfqDetectorService.new(rfq_email(from: "newsletter@mailchimp.com"))
    result = service.detect
    assert_equal false, result[:is_rfq]
  end

  test "keyword_detect — EXCLUDED_SUBJECT_PATTERNS 매칭 제외" do
    service = Gmail::RfqDetectorService.new(rfq_email(subject: "Invoice Notification - Payment Received"))
    result = service.detect
    assert_equal false, result[:is_rfq]
  end

  test "keyword_detect — Ariba 발신자는 즉시 rfq confirmed" do
    service = Gmail::RfqDetectorService.new(rfq_email(from: "sourcing@ariba.com"))
    result = service.detect
    assert result[:is_rfq]
    assert result[:is_ariba]
    assert_equal :confirmed, result[:rfq_verdict]
    assert_equal 95, result[:score]
  end

  test "keyword_detect — due_date 추출 ISO 형식" do
    service = Gmail::RfqDetectorService.new(rfq_email(body: "Delivery date: 2026-12-31"))
    result = service.keyword_detect
    assert_equal Date.new(2026, 12, 31), result[:due_date]
  end

  test "keyword_detect — due_date 없으면 nil" do
    service = Gmail::RfqDetectorService.new(rfq_email(body: "no date here"))
    result = service.keyword_detect
    assert_nil result[:due_date]
  end

  test "keyword_detect — customer_name From 헤더에서 추출" do
    service = Gmail::RfqDetectorService.new(rfq_email(from: "John Smith <john@company.com>"))
    result = service.keyword_detect
    assert_equal "John Smith", result[:customer_name]
  end
end
