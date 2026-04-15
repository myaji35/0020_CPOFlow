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

    order.destroy
    supplier.destroy
  end
end
