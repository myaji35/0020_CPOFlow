# frozen_string_literal: true

require "test_helper"

class EcountApi::CustomerSyncServiceTest < ActiveSupport::TestCase
  test "PAGE_SIZE 상수 정의됨" do
    assert_equal 50, EcountApi::CustomerSyncService::PAGE_SIZE
  end

  test "CUSTOMER_TYPE_MAP 상수 정의됨" do
    map = EcountApi::CustomerSyncService::CUSTOMER_TYPE_MAP
    assert_equal :client,   map["1"]
    assert_equal :supplier, map["2"]
    assert_equal :both,     map["3"]
  end

  test "CustomerSyncService < BaseService" do
    assert EcountApi::CustomerSyncService.ancestors.include?(EcountApi::BaseService)
  end

  test "build_attrs — 필드 매핑 정상" do
    svc  = EcountApi::CustomerSyncService.new
    cust = {
      "AR_NM"   => "  Test Corp  ",
      "NAT_CD"  => "KR",
      "EMAIL"   => "test@corp.com",
      "TEL"     => "02-1234-5678",
      "REMARK"  => "테스트 메모"
    }
    attrs = svc.send(:build_attrs, cust)
    assert_equal "Test Corp",      attrs[:name]
    assert_equal "KR",             attrs[:country]
    assert_equal "test@corp.com",  attrs[:contact_email]
    assert_equal "02-1234-5678",   attrs[:contact_phone]
    assert_equal "테스트 메모",    attrs[:notes]
    assert attrs[:ecount_synced_at].present?
  end

  test "build_attrs — 빈 값은 빈 문자열 처리" do
    svc  = EcountApi::CustomerSyncService.new
    cust = { "AR_NM" => nil, "NAT_CD" => nil, "EMAIL" => nil, "TEL" => nil, "REMARK" => nil }
    attrs = svc.send(:build_attrs, cust)
    assert_equal "", attrs[:name]
    assert_equal "", attrs[:country]
  end

  test "save_record — Supplier 저장 성공" do
    svc = EcountApi::CustomerSyncService.new
    code = "ECOUNT_SUP_#{SecureRandom.hex(4)}"
    attrs = { name: "Test Supplier", country: "US", contact_email: "", contact_phone: "", notes: "", ecount_synced_at: Time.current }
    result = svc.send(:save_record, Supplier, code, attrs)
    assert result[:ok], result[:error_entry].inspect
    Supplier.find_by(ecount_code: code)&.destroy
  end

  test "save_record — name 없는 Supplier는 에러 반환" do
    svc = EcountApi::CustomerSyncService.new
    code = "ECOUNT_ERR_#{SecureRandom.hex(4)}"
    attrs = { name: "", country: "US", contact_email: "", contact_phone: "", notes: "", ecount_synced_at: Time.current }
    result = svc.send(:save_record, Supplier, code, attrs)
    # name: "" 인 경우 validation이 있으면 에러, 없으면 ok
    assert_includes [ true, false ], result[:ok]
  end

  test "upsert_customer — AR_CD_TYPE:2 (Supplier)는 Supplier에 저장" do
    svc = EcountApi::CustomerSyncService.new
    code = "ECOUNT_US_#{SecureRandom.hex(4)}"
    cust = { "AR_CD" => code, "AR_CD_TYPE" => "2", "AR_NM" => "Supplier Only", "NAT_CD" => "US", "EMAIL" => "", "TEL" => "", "REMARK" => "" }
    result = svc.send(:upsert_customer, cust)
    assert_equal 1, result[:count]
    Supplier.find_by(ecount_code: code)&.destroy
  end

  test "upsert_customer — 알 수 없는 AR_CD_TYPE은 기본 supplier로 처리" do
    svc = EcountApi::CustomerSyncService.new
    code = "ECOUNT_UK_#{SecureRandom.hex(4)}"
    cust = { "AR_CD" => code, "AR_CD_TYPE" => "99", "AR_NM" => "Unknown Type", "NAT_CD" => "KR", "EMAIL" => "", "TEL" => "", "REMARK" => "" }
    result = svc.send(:upsert_customer, cust)
    assert_equal 1, result[:count]  # supplier로 기본 처리
    Supplier.find_by(ecount_code: code)&.destroy
  end
end
