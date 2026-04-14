# frozen_string_literal: true

require "test_helper"

class Gmail::EmailAttachmentExtractorServiceTest < ActiveSupport::TestCase
  test "MAX_ATTACHMENT_SIZE 상수 정의됨" do
    assert_equal 20.megabytes, Gmail::EmailAttachmentExtractorService::MAX_ATTACHMENT_SIZE
  end

  test "SUPPORTED_MIME_TYPES 상수 — PDF 포함" do
    assert_includes Gmail::EmailAttachmentExtractorService::SUPPORTED_MIME_TYPES, "application/pdf"
  end

  test "SUPPORTED_MIME_TYPES 상수 — Excel 포함" do
    assert_includes Gmail::EmailAttachmentExtractorService::SUPPORTED_MIME_TYPES, "application/vnd.ms-excel"
  end

  test "LINK_FILE_EXTENSIONS 상수 — .url/.lnk/.webloc 포함" do
    exts = Gmail::EmailAttachmentExtractorService::LINK_FILE_EXTENSIONS
    assert_includes exts, ".url"
    assert_includes exts, ".lnk"
    assert_includes exts, ".webloc"
  end

  test "SAP_URL_PATTERN — ariba URL 매칭" do
    pattern = Gmail::EmailAttachmentExtractorService::SAP_URL_PATTERN
    url     = "https://service.ariba.com/ad/supplier/rfq"
    assert_match pattern, url
  end

  test "ARIBA_AD_PATTERN — ariba /ad/ URL 매칭" do
    pattern = Gmail::EmailAttachmentExtractorService::ARIBA_AD_PATTERN
    url     = "https://service.ariba.com/ad/supplier/rfq/12345"
    assert_match pattern, url
  end

  test "link_file? — .url 확장자 인식" do
    user     = User.find_or_create_by!(email: "attach_ext_test@example.com") do |u|
      u.name = "Attach Ext"; u.password = "password123"; u.role = :member
    end
    supplier = Supplier.find_or_create_by!(name: "Attach Ext Supplier") { |s| s.code = "AEX#{SecureRandom.hex(2)}" }
    order    = Order.create!(title: "Attach Ext Order", status: :new_rfq,
                              customer_name: "Test", user: user, supplier: supplier)
    svc = Gmail::EmailAttachmentExtractorService.new(nil, nil, order)
    assert svc.send(:link_file?, "portal-link.url")
    assert_not svc.send(:link_file?, "document.pdf")
    order.destroy
    supplier.destroy
  end
end
