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
end
