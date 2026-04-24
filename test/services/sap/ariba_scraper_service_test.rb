# frozen_string_literal: true

require "test_helper"

class Sap::AribaScraperServiceTest < ActiveSupport::TestCase
  test "ARIBA_LINK_PATTERN — ariba /ad/ URL 매칭" do
    pattern = Sap::AribaScraperService::ARIBA_LINK_PATTERN
    assert_match pattern, "https://service.ariba.com/ad/supplier/rfq/12345"
  end

  test "ARIBA_LINK_PATTERN — 인증 링크 제외" do
    pattern = Sap::AribaScraperService::ARIBA_LINK_PATTERN
    assert_no_match pattern, "https://service.ariba.com/ad/pswdReset"
    assert_no_match pattern, "https://service.ariba.com/ad/Authenticator"
  end

  test "fetch_pdfs_for_order — sap_portal_links 없는 order 시 empty 반환" do
    user  = User.find_or_create_by!(email: "ariba_svc_test@example.com") do |u|
      u.name = "Ariba Svc Test"; u.password = "password123"; u.role = :member
    end
    supplier = Supplier.find_or_create_by!(name: "Ariba Svc Supplier") { |s| s.code = "ARBSVC#{SecureRandom.hex(2)}" }
    order = Order.create!(
      title:         "Ariba Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          user,
      supplier:      supplier
    )

    svc    = Sap::AribaScraperService.new
    result = svc.fetch_pdfs_for_order(order)
    assert_equal [], result[:saved]
    assert_equal [], result[:errors]

    order.reload.destroy
    supplier.destroy
  end

  test "extract_ariba_links (class method) — sap_portal_links 없으면 빈 배열" do
    user  = User.find_or_create_by!(email: "ariba_cls_test@example.com") do |u|
      u.name = "Ariba Cls Test"; u.password = "password123"; u.role = :member
    end
    order = Order.create!(title: "Ariba Cls Test", customer_name: "C",
                          status: :new_rfq, user: user)
    result = Sap::AribaScraperService.extract_ariba_links(order)
    assert_equal [], result
    order.reload.destroy
  end

  test "extract_ariba_links (class method) — 이메일 바디의 ariba URL 추출" do
    user  = User.find_or_create_by!(email: "ariba_body_test@example.com") do |u|
      u.name = "Ariba Body Test"; u.password = "password123"; u.role = :member
    end
    order = Order.create!(
      title: "Ariba Body Test", customer_name: "C",
      status: :new_rfq, user: user,
      original_email_body: "Please visit https://service.ariba.com/ad/supplier/rfq/9999 for details"
    )
    result = Sap::AribaScraperService.extract_ariba_links(order)
    assert_includes result, "https://service.ariba.com/ad/supplier/rfq/9999"
    order.reload.destroy
  end

  test "extract_ariba_links — itemID 포함 링크 우선 정렬" do
    user  = User.find_or_create_by!(email: "ariba_sort_test@example.com") do |u|
      u.name = "Ariba Sort Test"; u.password = "password123"; u.role = :member
    end
    order = Order.create!(
      title: "Ariba Sort Test", customer_name: "C",
      status: :new_rfq, user: user,
      original_email_body: "https://service.ariba.com/ad/rfq/123 and https://service.ariba.com/ad/rfq/456?itemID=789"
    )
    result = Sap::AribaScraperService.extract_ariba_links(order)
    # itemID 포함 링크가 첫 번째
    first_link = result.first
    assert first_link.include?("itemID"), "itemID 링크가 우선 정렬되어야 함 (actual: #{first_link})"
    order.reload.destroy
  end

  test "AribaScraperService 인스턴스화 가능" do
    assert_nothing_raised { Sap::AribaScraperService.new }
  end
end
