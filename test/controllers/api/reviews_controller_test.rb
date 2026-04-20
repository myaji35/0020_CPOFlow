# frozen_string_literal: true

require "test_helper"

class Api::ReviewsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # 샘플 리뷰 5건 생성
    5.times do |i|
      Review.create!(
        rating: (i % 5) + 1,
        body: "테스트 피드백 본문입니다 #{i + 1}번 — 법무팀 개선 요청사항",
        email: "user#{i}@example.com",
        email_hash: Digest::SHA256.hexdigest("user#{i}@example.com"),
        status: %i[new_review triaged responded][i % 3],
        channel: :in_app
      )
    end
  end

  # acceptance (c): API 호출 시 50건 이내 JSON 목록 반환

  test "GET /api/reviews — 200 JSON 응답" do
    get api_reviews_path
    assert_response :success
    assert_equal "application/json", response.media_type
  end

  test "GET /api/reviews — JSON 구조 확인" do
    get api_reviews_path
    body = JSON.parse(response.body)
    assert body.key?("total"), "total 키 누락"
    assert body.key?("reviews"), "reviews 키 누락"
    assert_kind_of Array, body["reviews"]
  end

  test "GET /api/reviews — 50건 이내 반환" do
    # acceptance (c): 50건 이내 확인
    # 대량 데이터 생성 후 확인
    55.times do |i|
      Review.create!(
        rating: 3,
        body: "대량 테스트 피드백 #{i + 1}번 — CSV 컬럼 셀렉터 요청",
        status: :new_review
      )
    end

    get api_reviews_path
    body = JSON.parse(response.body)
    assert body["reviews"].size <= 50, "50건 초과: #{body['reviews'].size}건"
  end

  test "GET /api/reviews — email 원문 절대 미포함" do
    # acceptance (c): email 원문 누출 없음 검증
    get api_reviews_path
    body = JSON.parse(response.body)
    body["reviews"].each do |r|
      assert_nil r["email"], "리뷰 ID #{r['id']}에 email 원문이 포함됩니다 — 보안 위반"
    end
  end

  test "GET /api/reviews — email_hash만 포함 (원문 아님)" do
    get api_reviews_path
    body = JSON.parse(response.body)
    reviews_with_hash = body["reviews"].select { |r| r["email_hash"].present? }
    reviews_with_hash.each do |r|
      # email_hash는 64자 hex 문자열 (SHA-256)
      assert_match(/\A[0-9a-f]{64}\z/, r["email_hash"]) if r["email_hash"]
    end
  end

  test "GET /api/reviews — 로그인 없이 접근 가능" do
    get api_reviews_path
    assert_response :success
  end

  test "GET /api/reviews — 필수 JSON 키 확인" do
    get api_reviews_path
    body = JSON.parse(response.body)
    required_keys = %w[id rating body email email_hash status created_at channel user_agent]
    body["reviews"].first(3).each do |r|
      required_keys.each do |key|
        assert r.key?(key), "리뷰 JSON에 #{key} 키가 없습니다"
      end
    end
  end

  test "GET /api/reviews — status_public 값 확인 (new_review → new)" do
    Review.create!(rating: 5, body: "신규 피드백 테스트입니다.", status: :new_review)
    get api_reviews_path
    body = JSON.parse(response.body)
    new_reviews = body["reviews"].select { |r| r["status"] == "new" }
    # new_review 상태가 있으면 "new"로 노출되어야 함
    assert new_reviews.any?, "new_review 상태가 'new'로 노출되어야 합니다"
  end
end
