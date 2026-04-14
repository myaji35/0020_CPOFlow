# frozen_string_literal: true

require "test_helper"

class EcountApi::ProductSyncServiceTest < ActiveSupport::TestCase
  test "PAGE_SIZE 상수 정의됨" do
    assert_equal 50, EcountApi::ProductSyncService::PAGE_SIZE
  end

  test "ProductSyncService < BaseService" do
    assert EcountApi::ProductSyncService.ancestors.include?(EcountApi::BaseService)
  end

  test "upsert_product — 유효한 품목 저장" do
    svc  = EcountApi::ProductSyncService.new
    code = "PROD_TEST_#{SecureRandom.hex(4)}"
    item = {
      "PROD_CD"  => code,
      "PROD_DES" => "테스트 품목",
      "SIZE_DES" => "100x200",
      "UNIT"     => "EA",
      "CLASS_CD" => "MECH",
      "PRICE"    => "150.5",
      "CURR_CD"  => "USD",
      "USE_YN"   => "Y"
    }
    result = svc.send(:upsert_product, item)
    assert result[:ok]
    Product.find_by(ecount_code: code)&.destroy
  end

  test "upsert_product — CURR_CD 없을 때 USD 기본값" do
    svc  = EcountApi::ProductSyncService.new
    code = "PROD_DEFAULT_#{SecureRandom.hex(4)}"
    item = {
      "PROD_CD"  => code,
      "PROD_DES" => "기본통화 품목",
      "SIZE_DES" => "",
      "UNIT"     => "EA",
      "CLASS_CD" => "",
      "PRICE"    => "0",
      "CURR_CD"  => nil,
      "USE_YN"   => "N"
    }
    result = svc.send(:upsert_product, item)
    assert result[:ok]
    product = Product.find_by(ecount_code: code)
    assert_equal "USD", product.currency
    assert_not product.active
    product&.destroy
  end
end
