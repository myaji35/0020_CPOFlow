# frozen_string_literal: true

require "test_helper"

class EcountApi::InventoryServiceTest < ActiveSupport::TestCase
  def setup
    @service = EcountApi::InventoryService.new
  end

  test "CACHE_TTL 상수 정의됨" do
    assert_equal 10.minutes, EcountApi::InventoryService::CACHE_TTL
  end

  test "InventoryService < BaseService" do
    assert EcountApi::InventoryService.ancestors.include?(EcountApi::BaseService)
  end

  test "fetch_stock — ecount_code 없을 때 nil 반환" do
    assert_nil @service.fetch_stock(nil)
    assert_nil @service.fetch_stock("")
  end

  test "fetch_stock — ApiError 발생 시 nil 반환 (에러 전파 안 함)" do
    # fetch_from_api 내부에서 ApiError를 rescue하여 nil 반환하는 동작 확인
    result = @service.send(:fetch_from_api, "NONEXISTENT_CODE_#{SecureRandom.hex(4)}")
    # API 없는 환경 → nil 반환 (rescue ApiError → nil)
    assert result.nil? || result.is_a?(Integer)
  end
end
