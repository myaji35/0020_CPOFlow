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

  test "MAX_TEXT_LENGTH 상수 정의됨" do
    assert_equal 8_000, LinkAnalyzerService::MAX_TEXT_LENGTH
  end

  test "FETCH_TIMEOUT 상수 정의됨" do
    assert_equal 10, LinkAnalyzerService::FETCH_TIMEOUT
  end

  test "MAX_RESPONSE_SIZE 상수 정의됨" do
    assert_equal 2.megabytes, LinkAnalyzerService::MAX_RESPONSE_SIZE
  end

  test "valid_url? — http URL은 true" do
    svc = LinkAnalyzerService.new("http://example.com/page")
    assert svc.send(:valid_url?)
  end

  test "valid_url? — https URL은 true" do
    svc = LinkAnalyzerService.new("https://example.com/page")
    assert svc.send(:valid_url?)
  end

  test "valid_url? — ftp는 false" do
    svc = LinkAnalyzerService.new("ftp://example.com/file.txt")
    assert_not svc.send(:valid_url?)
  end

  test "skip_domain? — linkedin.com은 true" do
    svc = LinkAnalyzerService.new("https://linkedin.com/in/user")
    assert svc.send(:skip_domain?)
  end

  test "skip_domain? — example.com은 false" do
    svc = LinkAnalyzerService.new("https://example.com/rfq")
    assert_not svc.send(:skip_domain?)
  end

  test "private_ip? — 192.168.x.x는 true" do
    svc = LinkAnalyzerService.new("http://192.168.1.100/admin")
    assert svc.send(:private_ip?)
  end

  test "private_ip? — 10.x.x.x는 true" do
    svc = LinkAnalyzerService.new("http://10.0.0.1/api")
    assert svc.send(:private_ip?)
  end

  test "analyze — analyze 메서드 존재" do
    svc = LinkAnalyzerService.new("https://example.com")
    assert svc.respond_to?(:analyze)
  end

  test "analyze — 클래스 메서드 analyze 존재" do
    assert LinkAnalyzerService.respond_to?(:analyze)
  end

  test "analyze — skip_domain이면 에러 없이 실패 반환" do
    result = LinkAnalyzerService.analyze("https://facebook.com/group/test")
    assert_equal false, result[:success]
    assert result[:error].present?
  end

  test "analyze — accounts.google.com은 skip" do
    result = LinkAnalyzerService.analyze("https://accounts.google.com/signin")
    assert_equal false, result[:success]
  end
end
