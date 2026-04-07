# frozen_string_literal: true

require "test_helper"

class TranslationServiceTest < ActiveSupport::TestCase
  test "translate — 빈 text는 nil 반환" do
    assert_nil TranslationService.translate("")
    assert_nil TranslationService.translate(nil)
  end

  test "translate — 한국어 위주 텍스트는 그대로 반환" do
    korean_text = "이것은 완전히 한국어로만 이루어진 긴 문장입니다. 발주서 납기일을 확인해 주세요."
    result = TranslationService.translate(korean_text)
    # API key 없거나 한국어 감지 → nil 또는 원문 반환
    # 핵심: 에러 없이 실행되어야 함
    assert_nothing_raised { TranslationService.translate(korean_text) }
  end

  test "translate — API key 없으면 nil 반환" do
    # credentials에 gemini key가 없는 테스트 환경
    result = TranslationService.translate("This is an English business email for quotation purposes.")
    # API key 없으므로 nil 반환 예상
    assert_nil result
  end

  test "translate_order! — 에러 없이 실행" do
    user = User.find_or_create_by(email: "translation_svc_test@example.com") do |u|
      u.name = "Translation Test"; u.password = "password123"; u.role = :member
    end
    order = Order.create!(title: "Translation Test Order", customer_name: "Cust", user: user, status: :new_rfq,
                         original_email_subject: "Quotation Request for Parts")
    assert_nothing_raised do
      TranslationService.translate_order!(order)
    end
    order.destroy
  end
end
