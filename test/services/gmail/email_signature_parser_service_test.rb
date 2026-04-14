# frozen_string_literal: true

require "test_helper"

class Gmail::EmailSignatureParserServiceTest < ActiveSupport::TestCase
  SAMPLE_EMAIL_BODY = <<~TEXT
    안녕하세요, 견적 요청드립니다.

    감사합니다
    John Kim
    Sales Manager
    T: +82-2-1234-5678
    M: +82-10-9876-5432
    john@example.com
    www.example.com
    Example Corp.
    Seoul, Korea
  TEXT

  test "parse — name 추출" do
    result = Gmail::EmailSignatureParserService.parse(SAMPLE_EMAIL_BODY)
    assert result.key?(:name)
  end

  test "parse — phone 추출" do
    result = Gmail::EmailSignatureParserService.parse(SAMPLE_EMAIL_BODY)
    assert result[:phone].present? || result[:mobile].present?
  end

  test "parse — email 추출" do
    result = Gmail::EmailSignatureParserService.parse(SAMPLE_EMAIL_BODY)
    assert_equal "john@example.com", result[:email]
  end

  test "parse — raw 서명 블록 포함" do
    result = Gmail::EmailSignatureParserService.parse(SAMPLE_EMAIL_BODY)
    assert result.key?(:raw)
  end

  test "split — 서명 구분자 분리" do
    body_with_delimiter = "본문입니다.\n\n감사합니다\nJohn Kim\nManager"
    result = Gmail::EmailSignatureParserService.split(body_with_delimiter)
    assert result.key?(:body)
    assert result.key?(:signature)
  end

  test "split — 구분자 없으면 signature nil" do
    plain_body = "이 이메일은 서명 구분자가 없습니다."
    result = Gmail::EmailSignatureParserService.split(plain_body)
    assert_equal plain_body, result[:body]
    assert_nil result[:signature]
  end

  test "parse — 빈 본문은 오류 없이 처리" do
    result = Gmail::EmailSignatureParserService.parse("")
    assert result.is_a?(Hash)
  end

  test "parse — dash 구분자 이후를 서명으로 인식" do
    body = "본문 텍스트입니다.\n--\nJane Doe\njane@company.com"
    result = Gmail::EmailSignatureParserService.parse(body)
    assert result.key?(:email)
  end
end
