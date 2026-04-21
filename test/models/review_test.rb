# frozen_string_literal: true

require "test_helper"

class ReviewTest < ActiveSupport::TestCase
  def valid_attrs
    { rating: 4, body: "서비스가 전반적으로 좋습니다." }
  end

  # --- Validations ---

  test "유효한 리뷰 저장 성공" do
    review = Review.new(valid_attrs)
    assert review.valid?, review.errors.full_messages.inspect
    assert review.save
  end

  test "rating 없으면 invalid" do
    review = Review.new(valid_attrs.merge(rating: nil))
    assert_not review.valid?
    assert review.errors[:rating].any?
  end

  test "rating 0이면 invalid (1~5만 허용)" do
    review = Review.new(valid_attrs.merge(rating: 0))
    assert_not review.valid?
  end

  test "rating 6이면 invalid" do
    review = Review.new(valid_attrs.merge(rating: 6))
    assert_not review.valid?
  end

  test "rating 1~5 모두 valid" do
    (1..5).each do |r|
      review = Review.new(valid_attrs.merge(rating: r))
      assert review.valid?, "rating #{r} should be valid"
    end
  end

  test "body 없으면 invalid" do
    review = Review.new(valid_attrs.merge(body: nil))
    assert_not review.valid?
  end

  test "body 4자이면 너무 짧아 invalid" do
    review = Review.new(valid_attrs.merge(body: "짧음"))
    assert_not review.valid?
  end

  test "body 4001자이면 너무 길어 invalid" do
    review = Review.new(valid_attrs.merge(body: "a" * 4001))
    assert_not review.valid?
  end

  test "body 4000자면 valid" do
    review = Review.new(valid_attrs.merge(body: "a" * 4000))
    assert review.valid?
  end

  # --- Status enum ---

  test "status 기본값 new_review" do
    review = Review.create!(valid_attrs)
    assert review.new_review?
    assert_equal "new", review.status_public
  end

  test "status_public: new_review → 'new'" do
    review = Review.new(valid_attrs.merge(status: "new_review"))
    assert_equal "new", review.status_public
  end

  test "status_public: triaged → 'triaged'" do
    review = Review.new(valid_attrs.merge(status: "triaged"))
    assert_equal "triaged", review.status_public
  end

  test "status 세터: 'new' 입력 → new_review 저장" do
    review = Review.new(valid_attrs)
    review.status = "new"
    assert review.new_review?
  end

  test "status 세터: 'triaged' 입력 → triaged 저장" do
    review = Review.new(valid_attrs)
    review.status = "triaged"
    assert review.triaged?
  end

  test "status 세터: 'responded' 입력 → responded 저장" do
    review = Review.new(valid_attrs)
    review.status = "responded"
    assert review.responded?
  end

  test "status 세터: 'archived' 입력 → archived 저장" do
    review = Review.new(valid_attrs)
    review.status = "archived"
    assert review.archived?
  end

  # --- Channel enum ---

  test "channel 기본값 in_app" do
    review = Review.create!(valid_attrs)
    assert review.in_app?
  end

  test "channel email 설정 가능" do
    review = Review.create!(valid_attrs.merge(channel: "email"))
    assert review.email?
  end

  # --- Email hash 로직 ---

  test "email 입력 시 before_save가 해시로 변환하고 원문을 nil로" do
    # P0 보안: 개인정보 보호 — 원문은 DB에 절대 저장되지 않음
    review = Review.create!(valid_attrs.merge(email: "test@example.com"))
    expected_hash = Digest::SHA256.hexdigest("test@example.com")
    assert_nil review.email, "email 원문이 nil이어야 함"
    assert_equal expected_hash, review.email_hash
  end

  test "email 대소문자/공백 정규화 후 해시" do
    review = Review.create!(valid_attrs.merge(email: "  TEST@Example.com  "))
    expected_hash = Digest::SHA256.hexdigest("test@example.com")
    assert_equal expected_hash, review.email_hash
  end

  test "email 형식 오류 시 invalid" do
    review = Review.new(valid_attrs.merge(email: "not-an-email"))
    assert_not review.valid?
    assert review.errors[:email].any?
  end

  test "email blank은 허용 (선택 필드)" do
    review = Review.new(valid_attrs.merge(email: ""))
    assert review.valid?
  end

  # --- to_review_json ---

  test "to_review_json email 원문 미포함" do
    review = Review.create!(valid_attrs.merge(email: "secret@example.com"))
    json = review.to_review_json
    assert_nil json[:email], "email 원문이 JSON에 포함되면 안 됩니다"
  end

  test "to_review_json 필수 키 포함" do
    review = Review.create!(valid_attrs)
    json = review.to_review_json
    %i[id rating body email email_hash status created_at channel user_agent].each do |key|
      assert json.key?(key), "JSON에 #{key} 키가 없습니다"
    end
  end

  test "to_review_json ID 형식 RV-XXX" do
    review = Review.create!(valid_attrs)
    json = review.to_review_json
    assert_match(/\ARV-\d{3,}\z/, json[:id])
  end
end
