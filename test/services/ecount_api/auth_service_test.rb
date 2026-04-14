# frozen_string_literal: true

require "test_helper"

class EcountApi::AuthServiceTest < ActiveSupport::TestCase
  def setup
    @service = EcountApi::AuthService.new
  end

  test "CACHE_KEY 상수 정의됨" do
    assert_equal :ecount_session_id, EcountApi::AuthService::CACHE_KEY
  end

  test "CACHE_EXPIRE 상수 정의됨" do
    assert_equal 23.hours, EcountApi::AuthService::CACHE_EXPIRE
  end

  test "AuthService < BaseService" do
    assert EcountApi::AuthService.ancestors.include?(EcountApi::BaseService)
  end

  test "invalidate! — エラーなし実行" do
    # NullStore 환경에서도 에러 없이 실행되어야 함
    assert_nothing_raised { @service.invalidate! }
  end

  test "session_id 클래스 메서드 존재" do
    assert EcountApi::AuthService.respond_to?(:session_id)
  end

  test "fetch_session_id 인스턴스 메서드 존재" do
    assert @service.respond_to?(:fetch_session_id)
  end

  test "credentials 미설정 시 AuthError 발생" do
    # production credentials가 없는 테스트 환경에서
    # ecount 키가 없으면 AuthError가 발생해야 함
    original = Rails.application.credentials.ecount rescue nil
    if original.nil?
      # credentials.ecount가 nil인 경우 credentials 메서드는 AuthError 발생
      assert_raises(EcountApi::AuthError) { @service.send(:credentials) }
    else
      # ecount credentials가 설정된 경우 에러 없이 통과
      assert_not_nil @service.send(:credentials)
    end
  end
end
