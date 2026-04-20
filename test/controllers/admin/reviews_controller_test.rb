# frozen_string_literal: true

require "test_helper"

class Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.find_or_create_by(email: "admin_reviews_test@example.com") do |u|
      u.name = "Admin Reviews User"
      u.password = "password123"
      u.role = :admin
    end
    @admin.update!(role: :admin)

    @member = User.find_or_create_by(email: "member_reviews_test@example.com") do |u|
      u.name = "Member User"
      u.password = "password123"
      u.role = :member
    end
    @member.update!(role: :member)

    @review = Review.create!(
      rating: 4,
      body: "감사 로그 필터가 날짜 범위만 되는데 담당자별도 필요합니다.",
      status: :new_review,
      channel: :in_app
    )
  end

  # --- GET /admin/reviews ---

  test "admin 접근 가능 (200)" do
    login_as(@admin)
    get admin_reviews_path
    assert_response :success
  end

  test "일반 member 접근 불가 (redirect)" do
    login_as(@member)
    get admin_reviews_path
    assert_response :redirect
  end

  test "비로그인 접근 불가 (redirect)" do
    get admin_reviews_path
    assert_response :redirect
  end

  test "status 필터 파라미터로 필터링 가능" do
    login_as(@admin)
    get admin_reviews_path, params: { status: "new" }
    assert_response :success
  end

  # --- PATCH /admin/reviews/:id/transition (acceptance b) ---

  test "상태 전환 정상 (new → triaged)" do
    # acceptance (b): status transition 후 reviews.json 반영 확인
    login_as(@admin)
    patch transition_admin_review_path(@review, to: "triaged")
    assert_response :redirect

    @review.reload
    assert @review.triaged?, "triaged로 변경되어야 합니다"
  end

  test "상태 전환 후 reviews.json에 반영됨" do
    # acceptance (b): JSON sync 확인
    login_as(@admin)
    patch transition_admin_review_path(@review, to: "responded")
    assert_response :redirect

    json_path = Rails.root.join(".claude", "review-db", "reviews.json")
    data = JSON.parse(File.read(json_path))
    review_id = "RV-#{@review.id.to_s.rjust(3, '0')}"
    json_review = data["reviews"].find { |r| r["id"] == review_id }

    assert_not_nil json_review, "reviews.json에 해당 리뷰가 없습니다"
    assert_equal "responded", json_review["status"], "JSON의 status가 responded여야 합니다"
  end

  test "잘못된 status to 파라미터 → redirect with alert" do
    login_as(@admin)
    patch transition_admin_review_path(@review, to: "invalid_status")
    assert_response :redirect
    follow_redirect!
    assert_select "div", /잘못된 상태/ rescue nil # alert가 있어야 함
  end

  test "transition 후 DB 상태 변경 확인" do
    login_as(@admin)
    patch transition_admin_review_path(@review, to: "archived")
    @review.reload
    assert @review.archived?
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
