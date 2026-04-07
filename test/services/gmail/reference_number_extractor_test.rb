# frozen_string_literal: true

require "test_helper"

class Gmail::ReferenceNumberExtractorTest < ActiveSupport::TestCase
  test "10자리 6-9 시작 숫자 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("Order 6000009324 received")
    assert_equal "6000009324", result
  end

  test "RFQ_ 형식 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("RFQ_6000009486 견적 요청")
    assert_equal "6000009486", result
  end

  test "RFQ- 형식 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("RFQ-2024001 발주")
    assert_equal "2024001", result
  end

  test "PO- 형식 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("PO-123456 확인 바랍니다")
    assert_equal "PO123456", result
  end

  test "9~10자리 일반 발주번호 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("발주번호 123456789")
    assert_equal "123456789", result
  end

  test "본문에서 발주번호 추출" do
    result = Gmail::ReferenceNumberExtractor.extract("제목 없음", "본문에 7000001234 포함")
    assert_equal "7000001234", result
  end

  test "발주번호 없으면 nil 반환" do
    result = Gmail::ReferenceNumberExtractor.extract("일반 이메일 제목", "본문 내용")
    assert_nil result
  end

  test "빈 subject/body 처리" do
    result = Gmail::ReferenceNumberExtractor.extract("", "")
    assert_nil result
  end

  test "제목이 우선 추출됨" do
    result = Gmail::ReferenceNumberExtractor.extract("6000009111 제목", "8000002222 본문")
    assert_equal "6000009111", result
  end

  test "본문은 첫 500자만 탐색" do
    long_body = "a" * 501 + " 6000009999"
    result = Gmail::ReferenceNumberExtractor.extract("", long_body)
    assert_nil result  # 500자 이후라 탐색 안됨
  end
end
