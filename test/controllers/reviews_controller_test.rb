# frozen_string_literal: true

require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  def valid_params
    { review: { rating: "4", body: "DPA 체결 플로우가 깔끔합니다. 법무팀 보고에 바로 활용 가능합니다." } }
  end

  # --- GET /reviews/new ---

  test "GET /reviews/new — 로그인 없이 접근 가능 (200)" do
    get new_review_path
    assert_response :success
  end

  # --- POST /reviews (정상 생성) ---

  test "POST /reviews — 정상 생성 → redirect" do
    # acceptance (a): Review.create + reviews.json append
    assert_difference("Review.count", 1) do
      post reviews_path, params: valid_params
    end
    # 성공 후 root_path로 redirect (root는 로그인 required → sign_in으로 redirect)
    assert_response :redirect
  end

  test "POST /reviews — reviews.json에 append 됨" do
    # acceptance (a): JSON 파일 append 확인
    json_path = Rails.root.join(".claude", "review-db", "reviews.json")
    before_ids = begin
      data = JSON.parse(File.read(json_path))
      data["reviews"].map { |r| r["id"] }
    rescue
      []
    end

    post reviews_path, params: valid_params
    assert_response :redirect

    review = Review.last
    after_data = JSON.parse(File.read(json_path))
    after_ids = after_data["reviews"].map { |r| r["id"] }
    new_id = "RV-#{review.id.to_s.rjust(3, '0')}"
    assert_includes after_ids, new_id, "reviews.json에 새 리뷰 ID가 없습니다"
  end

  test "POST /reviews — email 해시 옵션 1이면 email nil + email_hash 저장" do
    params = valid_params.merge(
      review: valid_params[:review].merge(email: "cpo@lawfirm.co.kr"),
      hash_email: "1"
    )
    post reviews_path, params: params
    assert_response :redirect

    review = Review.last
    assert_nil review.email, "email이 nil이어야 합니다"
    expected_hash = Digest::SHA256.hexdigest("cpo@lawfirm.co.kr")
    assert_equal expected_hash, review.email_hash
  end

  test "POST /reviews — email 해시 옵션 없으면 email 원문 저장" do
    params = valid_params.merge(
      review: valid_params[:review].merge(email: "open@example.com")
    )
    post reviews_path, params: params
    assert_response :redirect

    review = Review.last
    assert_equal "open@example.com", review.email
  end

  # --- POST /reviews (검증 실패) ---

  test "POST /reviews — rating 없으면 422" do
    post reviews_path, params: { review: { rating: nil, body: "테스트 본문입니다." } }
    assert_response :unprocessable_entity
  end

  test "POST /reviews — body 없으면 422" do
    post reviews_path, params: { review: { rating: "3", body: "" } }
    assert_response :unprocessable_entity
  end

  test "POST /reviews — body 너무 짧으면 422" do
    post reviews_path, params: { review: { rating: "3", body: "짧음" } }
    assert_response :unprocessable_entity
  end

  test "POST /reviews — 검증 실패 시 DB 레코드 생성 안 됨" do
    assert_no_difference("Review.count") do
      post reviews_path, params: { review: { rating: nil, body: "" } }
    end
  end
end
