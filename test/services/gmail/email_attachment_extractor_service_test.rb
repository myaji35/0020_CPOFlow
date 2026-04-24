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
    order.reload.destroy
    supplier.destroy
  end

  def build_svc
    user = User.find_or_create_by!(email: "attach_svc_helper@example.com") do |u|
      u.name = "Attach SVC Helper"; u.password = "password123"; u.role = :member
    end
    order = Order.find_or_create_by!(title: "Attach SVC Helper Order",
                                      customer_name: "C", status: :new_rfq, user: user)
    Gmail::EmailAttachmentExtractorService.new(nil, nil, order)
  end

  test "link_file? — .lnk 확장자 인식" do
    assert build_svc.send(:link_file?, "file.lnk")
  end

  test "link_file? — .webloc 확장자 인식" do
    assert build_svc.send(:link_file?, "bookmark.webloc")
  end

  test "link_file? — 빈 문자열은 false" do
    svc = build_svc
    assert_not svc.send(:link_file?, "")
    assert_not svc.send(:link_file?, nil)
  end

  test "supported_mime_type? — application/pdf는 true" do
    assert build_svc.send(:supported_mime_type?, "application/pdf")
  end

  test "supported_mime_type? — image/jpeg는 true" do
    assert build_svc.send(:supported_mime_type?, "image/jpeg")
  end

  test "supported_mime_type? — text/csv는 true" do
    assert build_svc.send(:supported_mime_type?, "text/csv")
  end

  test "supported_mime_type? — video/mp4는 false" do
    assert_not build_svc.send(:supported_mime_type?, "video/mp4")
  end

  test "extract_text_body — nil payload 시 빈 문자열" do
    assert_equal "", build_svc.send(:extract_text_body, nil)
  end

  test "extract_html_body — nil payload 시 빈 문자열" do
    assert_equal "", build_svc.send(:extract_html_body, nil)
  end

  test "extract_text_body — text/plain payload 처리" do
    ExtBodyMock = Struct.new(:data) unless defined?(ExtBodyMock)
    ExtPayloadMock = Struct.new(:mime_type, :body, :parts) unless defined?(ExtPayloadMock)
    payload = ExtPayloadMock.new("text/plain", ExtBodyMock.new(Base64.urlsafe_encode64("Hello plain")), nil)
    assert_equal "Hello plain", build_svc.send(:extract_text_body, payload)
  end

  test "extract_html_body — text/html payload 처리" do
    ExtBodyMock2 = Struct.new(:data) unless defined?(ExtBodyMock2)
    ExtPayloadMock2 = Struct.new(:mime_type, :body, :parts) unless defined?(ExtPayloadMock2)
    html = "<p>Hello HTML</p>"
    payload = ExtPayloadMock2.new("text/html", ExtBodyMock2.new(Base64.urlsafe_encode64(html)), nil)
    assert_equal html, build_svc.send(:extract_html_body, payload)
  end

  test "ARIBA_AD_PATTERN — 인증 링크 제외" do
    pattern = Gmail::EmailAttachmentExtractorService::ARIBA_AD_PATTERN
    assert_no_match pattern, "https://service.ariba.com/ad/pswdReset"
  end

  test "SAP_URL_PATTERN — SAP URL 매칭" do
    pattern = Gmail::EmailAttachmentExtractorService::SAP_URL_PATTERN
    assert_match pattern, "https://sap.example.com/sourcing/rfq"
  end
end
