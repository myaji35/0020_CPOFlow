# frozen_string_literal: true

require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "calendar_test@example.com") do |u|
      u.name     = "Calendar Test User"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)
  end

  test "calendar index 200 응답" do
    get calendar_path
    assert_response :success
  end

  # 9335fab "feat(i18n): ISS-324 Part 2 — calendar 영역 i18n" 이후 뷰는
  # I18n.l(@month, format: "%Y-%m") 를 쓴다. 표시 형식이 "2026년 03월" → "2026-03"으로
  # 바뀌었는데 테스트만 옛 형식에 남아 깨졌다. (로케일과 무관한 형식이다)
  test "calendar index — 이번 달 표시" do
    get calendar_path
    assert_response :success
    assert_match Date.today.strftime("%Y-%m"), response.body
  end

  test "calendar index — 특정 월 파라미터" do
    get calendar_path(month: "2026-03-01")
    assert_response :success
    assert_match "2026-03", response.body
  end

  test "calendar index — 캘린더 그리드 렌더링" do
    get calendar_path
    assert_response :success
    # 7일 컬럼 헤더 포함 확인
    assert_match "일", response.body
    assert_match "월", response.body
    assert_match "토", response.body
  end

  test "calendar weekly view 200 응답" do
    get calendar_path(view: "weekly")
    assert_response :success
  end

  test "calendar weekly view — 특정 날짜 파라미터" do
    get calendar_path(view: "weekly", date: "2026-04-16")
    assert_response :success
    assert_match "04/12", response.body # week start (Sunday)
  end

  test "calendar monthly view — 오늘 강조" do
    get calendar_path
    assert_response :success
    assert_match "ring-blue-400", response.body
  end

  test "calendar index — 납기 주문 히트맵 포함" do
    order = Order.create!(
      title: "Calendar Test Order",
      customer_name: "Cust",
      user: @user,
      status: :new_rfq,
      due_date: Date.today
    )

    get calendar_path
    assert_response :success
    # 오늘 납기 주문이 캘린더에 표시됨
    assert_match "Calendar Test Order", response.body

    order.reload.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
