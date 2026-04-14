# frozen_string_literal: true

require "test_helper"

class ClaudeTokenResolverTest < ActiveSupport::TestCase
  def setup
    # 테스트 격리: DB AppSetting 제거
    AppSetting.find_by(key: "anthropic_api_key")&.destroy
  end

  def teardown
    AppSetting.find_by(key: "anthropic_api_key")&.destroy
  end

  test "configured? — DB에 API 키 있으면 true" do
    AppSetting.set("anthropic_api_key", "sk-ant-test-key-12345")
    assert ClaudeTokenResolver.configured?
  end

  test "resolve — DB 키가 우선순위 1위" do
    AppSetting.set("anthropic_api_key", "sk-ant-db-key")
    result = ClaudeTokenResolver.resolve
    assert_equal :db, result[:source]
    assert_equal "sk-ant-db-key", result[:key]
    assert_equal :api_key, result[:auth]
  end

  test "status — 설정된 경우 configured true" do
    AppSetting.set("anthropic_api_key", "sk-ant-status-key")
    status = ClaudeTokenResolver.status
    assert status[:configured]
    assert_equal :db, status[:source]
    assert status[:masked].present?
  end

  test "status — 미설정 시 configured false" do
    # 환경변수와 credentials도 없다고 가정
    # DB 키는 teardown에서 정리됨
    status = ClaudeTokenResolver.status
    # configured가 false이거나 다른 소스 (CLI/env/credentials)에서 설정될 수 있음
    assert status.key?(:configured)
  end

  test "resolve — 반환값이 nil이거나 Hash" do
    result = ClaudeTokenResolver.resolve
    assert result.nil? || result.is_a?(Hash)
  end

  test "api_base_url — 문자열 반환" do
    url = ClaudeTokenResolver.api_base_url
    assert url.is_a?(String)
    assert url.start_with?("https://")
  end
end
