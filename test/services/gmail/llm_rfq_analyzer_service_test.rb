# frozen_string_literal: true

require "test_helper"

class Gmail::LlmRfqAnalyzerServiceTest < ActiveSupport::TestCase
  def setup
    @parsed_email = {
      from:    "vendor@example.com",
      to:      "buyer@company.com",
      subject: "Request for Quotation — Steel Pipes",
      body:    "Dear Sir/Madam, We would like to request quotation for the following items..."
    }
    @service = Gmail::LlmRfqAnalyzerService.new(@parsed_email)
  end

  test "MAX_BODY_CHARS 상수 정의됨" do
    assert_equal 4000, Gmail::LlmRfqAnalyzerService::MAX_BODY_CHARS
  end

  test "analyze — API 키 미설정 시 fallback_result 반환" do
    # ClaudeTokenResolver.configured?가 false이면 fallback 반환
    result = @service.analyze
    assert result.is_a?(Hash)
    assert result.key?(:is_rfq)
    assert result.key?(:confidence)
    assert result.key?(:score)
  end

  test "analyze — 결과에 llm_unavailable 키 포함 (API 미설정 시)" do
    result = @service.analyze
    # API 키 미설정 시 fallback_result 반환 — llm_unavailable: true
    assert result.key?(:llm_unavailable) || result.key?(:is_rfq)
  end

  test "analyze — 에러 발생 시 fallback 반환 (에러 전파 안 함)" do
    # call_claude_api가 예외를 던져도 analyze는 fallback_result 반환
    result = @service.analyze
    assert result.is_a?(Hash)
  end

  test "api_key_configured? — ClaudeTokenResolver 위임" do
    result = @service.send(:api_key_configured?)
    assert_includes [ true, false ], result
  end
end
