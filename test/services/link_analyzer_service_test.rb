# frozen_string_literal: true

require "test_helper"

class LinkAnalyzerServiceTest < ActiveSupport::TestCase
  test "analyze — 빈 URL은 오류 없이 실패 반환" do
    result = LinkAnalyzerService.analyze("")
    assert_equal false, result[:success]
  end

  test "analyze — 잘못된 URL 형식" do
    result = LinkAnalyzerService.analyze("not-a-url")
    assert_equal false, result[:success]
  end

  test "analyze — skip 도메인 (linkedin.com) 즉시 실패" do
    result = LinkAnalyzerService.analyze("https://linkedin.com/in/testuser")
    assert_equal false, result[:success]
  end

  test "analyze — 내부 IP SSRF 차단" do
    result = LinkAnalyzerService.analyze("http://192.168.1.1/admin")
    assert_equal false, result[:success]
  end

  test "analyze — localhost SSRF 차단" do
    result = LinkAnalyzerService.analyze("http://127.0.0.1:8080/secret")
    assert_equal false, result[:success]
  end

  test "PRIVATE_IP_RANGES 상수 정의됨" do
    assert LinkAnalyzerService::PRIVATE_IP_RANGES.is_a?(Array)
    assert LinkAnalyzerService::PRIVATE_IP_RANGES.length > 0
  end

  test "SKIP_DOMAINS 상수에 주요 소셜 도메인 포함" do
    assert_includes LinkAnalyzerService::SKIP_DOMAINS, "linkedin.com"
    assert_includes LinkAnalyzerService::SKIP_DOMAINS, "facebook.com"
  end
end
