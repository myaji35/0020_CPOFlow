# frozen_string_literal: true

require "test_helper"

class EcountApi::ProductSyncServiceTest < ActiveSupport::TestCase
  test "CHUNK_SIZE 상수 정의됨" do
    assert_equal 500, EcountApi::ProductSyncService::CHUNK_SIZE
  end

  test "UPDATE_COLS 상수 — 주요 필드 포함" do
    cols = EcountApi::ProductSyncService::UPDATE_COLS
    assert_includes cols, :name
    assert_includes cols, :currency
    assert_includes cols, :active
  end

  test "ProductSyncService < BaseService" do
    assert EcountApi::ProductSyncService.ancestors.include?(EcountApi::BaseService)
  end

  test "product_attrs — 기본 매핑 정상" do
    svc  = EcountApi::ProductSyncService.new
    item = {
      "PROD_CD"  => "TEST_CODE_#{SecureRandom.hex(4)}",
      "PROD_DES" => " 테스트 품목 ",
      "SIZE_DES" => "100x200",
      "UNIT"     => "EA",
      "CLASS_CD" => "MECH",
      "IN_PRICE" => "150.5",
      "CURR_CD"  => "USD",
      "USE_YN"   => "Y"
    }
    attrs = svc.send(:product_attrs, item)
    assert_equal item["PROD_CD"], attrs[:ecount_code]
    assert_equal "테스트 품목",  attrs[:name]
    assert_equal "USD",           attrs[:currency]
    assert attrs[:active]
  end

  test "product_attrs — PROD_CD 없으면 nil 반환" do
    svc  = EcountApi::ProductSyncService.new
    item = { "PROD_CD" => "", "PROD_DES" => "빈코드" }
    assert_nil svc.send(:product_attrs, item)
  end

  test "product_attrs — CURR_CD 없을 때 USD 기본값" do
    svc  = EcountApi::ProductSyncService.new
    item = {
      "PROD_CD"  => "DEFAULT_CURR_#{SecureRandom.hex(4)}",
      "PROD_DES" => "기본통화",
      "SIZE_DES" => "", "UNIT" => "EA", "CLASS_CD" => "",
      "IN_PRICE" => "0", "CURR_CD" => nil, "USE_YN" => "N"
    }
    attrs = svc.send(:product_attrs, item)
    assert_equal "USD", attrs[:currency]
    assert_not attrs[:active]
  end

  test "extract_result — Array 그대로 반환" do
    svc  = EcountApi::ProductSyncService.new
    data = [{ "PROD_CD" => "A" }, { "PROD_CD" => "B" }]
    assert_equal data, svc.send(:extract_result, data)
  end

  test "extract_result — 빈 배열 반환" do
    svc = EcountApi::ProductSyncService.new
    assert_equal [], svc.send(:extract_result, nil)
    assert_equal [], svc.send(:extract_result, "string")
  end
end
