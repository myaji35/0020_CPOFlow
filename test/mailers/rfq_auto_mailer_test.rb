require "test_helper"

# ISS-358 Wave 4 (T12) — RfqAutoMailer 7컬럼 양식 + dual-key 렌더 테스트.
# Wave 2 (commits 1dedf33/1a38311) 에서 신설된 AtoZ RFQ 양식이
# string-key / symbol-key item 양쪽 모두를 정상 렌더하는지 검증.
class RfqAutoMailerTest < ActionMailer::TestCase
  setup do
    I18n.locale = :ko
    @sender = User.find_or_create_by!(email: "rfq_test_sender@example.com") do |u|
      u.password = "password123"
      u.role = :member
      u.name = "RFQ Sender"
    end
    @order = Order.create!(
      title: "RFQ test #{SecureRandom.hex(3)}",
      customer_name: "TestClient",
      status: :new_rfq,
      user: @sender,
      rfq_no: "10999"
    )
    # Selection 은 mailer 가 .contact_email / .supplier_name 을 호출 → OpenStruct 로 stub
    @selection = OpenStruct.new(
      supplier_name: "Test Supplier",
      contact_email: "supplier@test.com"
    )
    @items = [
      {
        "name" => "SikaSet Plus",
        "spec" => "Concrete admixture\n10kg bag",
        "model" => "SP-100",
        "part_no" => "PN-001",
        "manufacturer" => "Sika",
        "unit" => "BAG",
        "quantity" => 50,
        "remarks" => "QC pass"
      },
      {
        name: "SikaProof",
        spec: "Waterproofing membrane",
        model: "SPM-200",
        manufacturer: "Sika",
        unit: "ROLL",
        quantity: 10,
        certification: "KS"
      }
    ]
  end

  teardown do
    @order&.destroy
    I18n.locale = I18n.default_locale
  end

  test "rfq_inquiry — Request For Quotation 헤더 노출 (html + text)" do
    mail = build_mail(inquiry_due_date: "5-May-26")
    assert_match(/Request For Quotation/, html_body(mail))
    assert_match(/Request For Quotation/, text_body(mail))
  end

  test "rfq_inquiry — 7컬럼 헤더 (Material/Model/Manufacturer/Unit/Qty/Remarks) 노출 (html)" do
    mail = build_mail(inquiry_due_date: "5-May-26")
    body = html_body(mail)
    assert_match(/Material Description/, body)
    assert_match(/Model.*Part No/, body)
    assert_match(/Manufacturer.*Brand/, body)
    assert_match(/Unit/, body)
    assert_match(/Qty/, body)
    assert_match(/Remarks/, body)
  end

  test "rfq_inquiry — string-key item 데이터 렌더 (B2 dual-key, html)" do
    mail = build_mail
    body = html_body(mail)
    assert_match(/SikaSet Plus/, body)
    assert_match(/PN-001/, body)
    assert_match(/Sika/, body)
  end

  test "rfq_inquiry — symbol-key item 데이터 렌더 (B2 dual-key, html)" do
    mail = build_mail
    body = html_body(mail)
    assert_match(/SikaProof/, body)
    assert_match(/SPM-200/, body)
  end

  test "rfq_inquiry — sender 이름/이메일 푸터에 노출 (html)" do
    mail = build_mail
    body = html_body(mail)
    assert_match(/RFQ Sender/, body)
    assert_match(/rfq_test_sender@example.com/, body)
  end

  test "rfq_inquiry — RFQ No. 헤더 표시 (html + text)" do
    mail = build_mail
    assert_match(/10999/, html_body(mail))
    assert_match(/10999/, text_body(mail))
  end

  test "rfq_inquiry — Inquiry Due Date 노출 (html + text)" do
    mail = build_mail(inquiry_due_date: "5-May-26")
    assert_match(/5-May-26/, html_body(mail))
    assert_match(/5-May-26/, text_body(mail))
  end

  test "rfq_inquiry — text part 동일 데이터 렌더 (T7 AtoZ 양식)" do
    mail = build_mail(inquiry_due_date: "5-May-26")
    text = text_body(mail)
    assert text.length > 0, "text part 비어있음"
    assert_match(/Request For Quotation/, text)
    assert_match(/SikaSet Plus/, text)
    assert_match(/Manufacturer/, text)
    assert_match(/5-May-26/, text)
  end

  test "rfq_inquiry — 수신자 + reply_to 정상 설정" do
    mail = build_mail
    assert_equal [ "supplier@test.com" ], mail.to
    assert_equal [ @sender.email ], mail.reply_to
  end

  test "rfq_inquiry — subject 에 RFQ + reference_no/title 포함" do
    mail = build_mail
    assert_match(/\[RFQ\]/, mail.subject)
  end

  private

  def build_mail(inquiry_due_date: nil)
    params = { selection: @selection, items: @items, order: @order, from_user: @sender }
    params[:inquiry_due_date] = inquiry_due_date if inquiry_due_date
    RfqAutoMailer.with(**params).rfq_inquiry
  end

  # multipart 메일 — html_part / text_part 로 접근. mail.body 는 빈 문자열.
  def html_body(mail)
    mail.html_part&.body.to_s
  end

  def text_body(mail)
    mail.text_part&.body.to_s
  end
end
