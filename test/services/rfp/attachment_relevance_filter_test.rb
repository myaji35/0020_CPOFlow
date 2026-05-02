require "test_helper"

class Rfp::AttachmentRelevanceFilterTest < ActiveSupport::TestCase
  # Mock attachment helper
  def fake_attachment(filename:, content_type: "application/pdf", byte_size: 10_000, body: nil)
    blob = Struct.new(:filename, :content_type, :byte_size).new(
      Pathname.new(filename), content_type, byte_size
    )
    att = Object.new
    att.define_singleton_method(:blob) { blob }
    if body
      att.define_singleton_method(:open) do |&block|
        require "stringio"
        block.call(StringIO.new(body))
      end
    else
      att.define_singleton_method(:open) { |&block| block.call(StringIO.new("")) }
    end
    att
  end

  test "ariba_page_*.pdf 파일명은 차단" do
    att = fake_attachment(filename: "ariba_page_1776137528624.pdf")
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant], "ariba_page는 노이즈로 차단되어야 함"
    assert_match(/filename pattern/, result[:reason])
  end

  test "ariba_login으로 시작하는 파일명은 차단" do
    att = fake_attachment(filename: "ariba_login_screenshot.png", content_type: "image/png")
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant]
  end

  test "captcha 포함 파일명은 차단" do
    att = fake_attachment(filename: "session_captcha_123.html", content_type: "text/html")
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant]
  end

  test "screenshot 패턴 차단" do
    att = fake_attachment(filename: "screenshot-1234.png", content_type: "image/png")
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant]
  end

  test "PDF Title이 'Ariba On-Demand Site'이면 차단" do
    pdf_body = "%PDF-1.4\n1 0 obj\n<</Title (Ariba On-Demand Site)\n/Creator (Chromium)>>\n"
    att = fake_attachment(filename: "downloaded.pdf", body: pdf_body)
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant]
    assert_match(/pdf title/, result[:reason])
  end

  test "2KB 미만 파일은 차단" do
    att = fake_attachment(filename: "tiny.pdf", byte_size: 1_500)
    result = Rfp::AttachmentRelevanceFilter.call(att)
    refute result[:relevant]
    assert_match(/size/, result[:reason])
  end

  test "정상 RFP 첨부는 통과 (10KB+ PDF, 일반 파일명)" do
    pdf_body = "%PDF-1.4\n1 0 obj\n<</Title (Quotation Request 6000009675)>>\n" + ("x" * 5000)
    att = fake_attachment(filename: "6000009675.pdf", byte_size: 10_000, body: pdf_body)
    result = Rfp::AttachmentRelevanceFilter.call(att)
    assert result[:relevant], "정상 RFP는 통과해야 함: #{result[:reason]}"
  end

  test "Ariba SAP Doc 형식 (6000xxx.doc) 통과" do
    att = fake_attachment(filename: "6000009675.doc", content_type: "text/html", byte_size: 42_000)
    result = Rfp::AttachmentRelevanceFilter.call(att)
    assert result[:relevant], "Ariba 실제 RFP는 통과: #{result[:reason]}"
  end

  test "에러 발생 시 안전 fallback (relevant=true)" do
    att = Object.new
    att.define_singleton_method(:blob) { raise "boom" }
    result = Rfp::AttachmentRelevanceFilter.call(att)
    assert result[:relevant], "예외 시 안전하게 통과시켜야 함 (false negative 방지)"
  end
end
