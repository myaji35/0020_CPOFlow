require "test_helper"

class QuoteAttachmentClassifierTest < ActiveSupport::TestCase
  # Mock attachment — Order 모델 validate_attachment_safety가 audio/video MIME을 거부하므로
  # ActiveStorage 대신 duck-typing Struct으로 classifier 인터페이스만 충족
  FakeFilename = Struct.new(:value) do
    def to_s = value
  end

  FakeAttachment = Struct.new(:filename_str, :content_type) do
    def filename = FakeFilename.new(filename_str)
  end

  def fake(filename, content_type)
    FakeAttachment.new(filename, content_type)
  end

  test "RFQ keyword filename → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(fake("RFQ-100.pdf", "application/pdf"))
  end

  test "MULKIYA keyword filename → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(fake("MULKIYA 29758.pdf", "application/pdf"))
  end

  test "lowercase rfq keyword → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(fake("rfq-100.pdf", "application/pdf"))
  end

  test "INVOICE keyword → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(fake("Invoice-2024.pdf", "application/pdf"))
  end

  test "audio MIME → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(fake("voice.mp3", "audio/mpeg"))
  end

  test "video MIME → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(fake("clip.mp4", "video/mp4"))
  end

  test "zip MIME → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(fake("docs.zip", "application/zip"))
  end

  # 옵션 C (대표님 결정 2026-05-11): :ambiguous 폐지 — 명백한 negative(MIME/키워드)만
  # 차단하고 나머지는 전부 :quote_candidate 로 [분석] 노출. 사용자 자율 판단.
  # 그때 구현만 바꾸고 이 테스트는 :ambiguous 기대를 유지해 2개월간 깨진 채였다.
  # (CI에서 테스트를 돌리지 않아 드러나지 않음 — 2026-07-15 게이트 도입으로 발견)
  test "PDF without keyword → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(fake("doc-12.pdf", "application/pdf"))
  end

  test "XLSX without keyword → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(fake("data.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
  end

  test "negative keyword overrides positive MIME" do
    # contract.pdf — PDF는 positive MIME이지만 CONTRACT는 negative keyword
    assert_equal :not_quote, QuoteAttachmentClassifier.call(fake("contract.pdf", "application/pdf"))
  end
end
