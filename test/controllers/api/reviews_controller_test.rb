# frozen_string_literal: true

require "test_helper"

class Api::ReviewsControllerTest < ActionDispatch::IntegrationTest
  API_KEY = "test-api-key-12345"

  def setup
    ENV["CPOFLOW_API_KEY"] = API_KEY
    # 샘플 리뷰 5건 생성 (before_save로 email 자동 해시)
    5.times do |i|
      Review.create!(
        rating: (i % 5) + 1,
        body: "테스트 피드백 본문입니다 #{i + 1}번 — 법무팀 개선 요청사항",
        email: "user#{i}@example.com",
        status: %i[new_review triaged responded][i % 3],
        channel: :in_app
      )
    end
  end

  def teardown
    ENV.delete("CPOFLOW_API_KEY")
  end

  def auth_headers
    { "X-CPOFlow-API-Key" => API_KEY }
  end

  # --- 인증 ---

  test "GET /api/reviews — API 키 없으면 401" do
    get api_reviews_path
    assert_response :unauthorized
  end

  test "GET /api/reviews — 잘못된 API 키는 401" do
    get api_reviews_path, headers: { "X-CPOFlow-API-Key" => "wrong-key" }
    assert_response :unauthorized
  end

  test "GET /api/reviews — 쿼리 파라미터로도 API 키 허용" do
    get api_reviews_path(api_key: API_KEY)
    assert_response :success
  end

  test "GET /api/reviews — 서버에 API 키 미설정 시 503" do
    ENV.delete("CPOFLOW_API_KEY")
    get api_reviews_path, headers: auth_headers
    assert_response :service_unavailable
  end

  # --- 정상 응답 ---

  test "GET /api/reviews — 200 JSON 응답 (API 키 인증)" do
    get api_reviews_path, headers: auth_headers
    assert_response :success
    assert_equal "application/json", response.media_type
  end

  test "GET /api/reviews — JSON 구조 확인" do
    get api_reviews_path, headers: auth_headers
    body = JSON.parse(response.body)
    assert body.key?("total"), "total 키 누락"
    assert body.key?("reviews"), "reviews 키 누락"
    assert_kind_of Array, body["reviews"]
  end

  test "GET /api/reviews — 50건 이내 반환" do
    55.times do |i|
      Review.create!(
        rating: 3,
        body: "대량 테스트 피드백 #{i + 1}번 — CSV 컬럼 셀렉터 요청",
        status: :new_review
      )
    end

    get api_reviews_path, headers: auth_headers
    body = JSON.parse(response.body)
    assert body["reviews"].size <= 50, "50건 초과: #{body['reviews'].size}건"
  end

  test "GET /api/reviews — email 원문 절대 미포함" do
    get api_reviews_path, headers: auth_headers
    body = JSON.parse(response.body)
    body["reviews"].each do |r|
      assert_nil r["email"], "리뷰 ID #{r['id']}에 email 원문이 포함됩니다 — 보안 위반"
    end
  end

  test "GET /api/reviews — email_hash만 포함 (원문 아님)" do
    get api_reviews_path, headers: auth_headers
    body = JSON.parse(response.body)
    reviews_with_hash = body["reviews"].select { |r| r["email_hash"].present? }
    reviews_with_hash.each do |r|
      assert_match(/\A[0-9a-f]{64}\z/, r["email_hash"]) if r["email_hash"]
    end
  end

  test "GET /api/reviews — 필수 JSON 키 확인" do
    get api_reviews_path, headers: auth_headers
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
    get api_reviews_path, headers: auth_headers
    body = JSON.parse(response.body)
    new_reviews = body["reviews"].select { |r| r["status"] == "new" }
    assert new_reviews.any?, "new_review 상태가 'new'로 노출되어야 합니다"
  end
end
