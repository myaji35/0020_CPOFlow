# frozen_string_literal: true

require "test_helper"

class EcountApi::BaseServiceTest < ActiveSupport::TestCase
  test "BASE_URL 상수 정의됨" do
    assert_equal "https://oapi.ecounterp.com/OAPI/V2", EcountApi::BaseService::BASE_URL
  end

  test "TIMEOUT 상수 정의됨" do
    assert_equal 30, EcountApi::BaseService::TIMEOUT
  end

  test "MAX_RETRIES 상수 정의됨" do
    assert_equal 3, EcountApi::BaseService::MAX_RETRIES
  end

  test "RETRY_DELAYS 상수 정의됨" do
    assert_equal [2, 4, 8], EcountApi::BaseService::RETRY_DELAYS
  end

  test "ApiError < StandardError" do
    assert EcountApi::ApiError.ancestors.include?(StandardError)
  end

  test "AuthError < ApiError" do
    assert EcountApi::AuthError.ancestors.include?(EcountApi::ApiError)
  end

  test "RateLimitError < ApiError" do
    assert EcountApi::RateLimitError.ancestors.include?(EcountApi::ApiError)
  end

  FakeResponse = Struct.new(:body)

  test "parse_response! — 0000 코드 시 DATA1 반환" do
    svc  = EcountApi::BaseService.new
    body = { "RESPONSE" => { "HEADER" => { "RESULT_CODE" => "0000" }, "DATA1" => [{ "id" => 1 }] } }
    result = svc.send(:parse_response!, FakeResponse.new(body.to_json))
    assert_equal [{ "id" => 1 }], result
  end

  test "parse_response! — DATA1 없을 때 빈 배열 반환" do
    svc  = EcountApi::BaseService.new
    body = { "RESPONSE" => { "HEADER" => { "RESULT_CODE" => "0000" } } }
    result = svc.send(:parse_response!, FakeResponse.new(body.to_json))
    assert_equal [], result
  end

  test "parse_response! — 4001 코드 시 RateLimitError 발생" do
    svc  = EcountApi::BaseService.new
    body = { "RESPONSE" => { "HEADER" => { "RESULT_CODE" => "4001", "RESULT_MSG" => "rate limit" } } }
    assert_raises(EcountApi::RateLimitError) { svc.send(:parse_response!, FakeResponse.new(body.to_json)) }
  end

  test "parse_response! — 4010 코드 시 AuthError 발생" do
    svc  = EcountApi::BaseService.new
    body = { "RESPONSE" => { "HEADER" => { "RESULT_CODE" => "4010", "RESULT_MSG" => "session expired" } } }
    assert_raises(EcountApi::AuthError) { svc.send(:parse_response!, FakeResponse.new(body.to_json)) }
  end

  test "parse_response! — 알 수 없는 코드 시 ApiError 발생" do
    svc  = EcountApi::BaseService.new
    body = { "RESPONSE" => { "HEADER" => { "RESULT_CODE" => "9999", "RESULT_MSG" => "unknown" } } }
    assert_raises(EcountApi::ApiError) { svc.send(:parse_response!, FakeResponse.new(body.to_json)) }
  end

  test "parse_response! — Status:200 + Data 구조 반환" do
    svc  = EcountApi::BaseService.new
    body = { "Status" => "200", "Data" => { "Result" => [{ "CODE" => "P001" }], "TotalCnt" => 1 } }
    result = svc.send(:parse_response!, FakeResponse.new(body.to_json))
    assert_equal({ "Result" => [{ "CODE" => "P001" }], "TotalCnt" => 1 }, result)
  end

  test "parse_response! — Status:4010은 AuthError 발생" do
    svc  = EcountApi::BaseService.new
    body = { "Status" => "4010", "Errors" => [{ "Message" => "session expired" }] }
    assert_raises(EcountApi::AuthError) { svc.send(:parse_response!, FakeResponse.new(body.to_json)) }
  end

  test "parse_response! — Status:4001은 RateLimitError 발생" do
    svc  = EcountApi::BaseService.new
    body = { "Status" => "4001", "Errors" => [{ "Message" => "rate limit" }] }
    assert_raises(EcountApi::RateLimitError) { svc.send(:parse_response!, FakeResponse.new(body.to_json)) }
  end

  test "check_quota! — nil이면 에러 없이 통과" do
    svc = EcountApi::BaseService.new
    assert_nothing_raised { svc.send(:check_quota!, nil) }
  end

  test "check_quota! — 사용량 50%이면 에러 없음" do
    svc = EcountApi::BaseService.new
    info = "1일 허용량 : 2500/5000건"
    assert_nothing_raised { svc.send(:check_quota!, info) }
  end

  test "base_url 클래스 메서드 존재" do
    assert_respond_to EcountApi::BaseService, :base_url
    assert_not_nil EcountApi::BaseService.base_url
  end

  test "login_base_url 클래스 메서드 존재" do
    assert_respond_to EcountApi::BaseService, :login_base_url
    assert_not_nil EcountApi::BaseService.login_base_url
  end
end
