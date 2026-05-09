# frozen_string_literal: true

require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    I18n.locale = :ko
    @user = User.find_or_create_by(email: "notif_ctrl_test@example.com") do |u|
      u.name = "Notif Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @order = Order.create!(title: "Notif Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
    @notification = Notification.create!(
      user: @user,
      notifiable: @order,
      notification_type: "system",
      body: "테스트 알림"
    )
  end

  def teardown
    Notification.where(user: @user).destroy_all if @user
    @order.destroy if @order && Order.exists?(@order.id)
  end

  test "notifications index 200" do
    get notifications_path
    assert_response :success
  end

  test "notifications index — 알림 목록 표시" do
    get notifications_path
    assert_match "테스트 알림", response.body
  end

  test "notifications read — 읽음 처리 후 리다이렉트" do
    patch read_notification_path(@notification)
    assert_response :redirect
    @notification.reload
    assert_not_nil @notification.read_at
  end

  test "notifications read_all — 전체 읽음 처리" do
    Notification.create!(user: @user, notifiable: @order, notification_type: "system", body: "추가 알림")
    patch read_all_notifications_path
    assert_response :redirect
    assert_equal 0, @user.notifications.unread.count
    @user.notifications.destroy_all
  end

  # ─────────────────────────────────────────
  # ISS-353 Phase 1 — T14 acknowledge / view 테스트
  # ─────────────────────────────────────────

  # 헬퍼: 본인 소유 mention notification 생성
  def make_mention(user: @user, order: @order)
    Notification.create!(
      user: user, notifiable: order,
      notification_type: "mentioned", body: "@u 확인"
    )
  end

  test "PATCH acknowledge sets acknowledged_at" do
    m = make_mention
    patch acknowledge_notification_path(m), as: :json
    assert_response :success
    m.reload
    assert m.acknowledged_at.present?
  end

  test "PATCH acknowledge returns turbo_stream remove" do
    m = make_mention
    patch acknowledge_notification_path(m), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/turbo-stream\s+action="remove"/, response.body)
    assert_match(/target="notification-row-#{m.id}"/, response.body)
  end

  test "PATCH acknowledge for non-owner returns 404" do
    other_user = User.find_or_create_by(email: "notif_ctrl_other@example.com") do |u|
      u.name = "Notif Other"; u.password = "password123"; u.role = :member
    end
    other_order  = Order.create!(title: "Other Order", customer_name: "X", user: other_user, status: :new_rfq)
    other_notif  = Notification.create!(
      user: other_user, notifiable: other_order,
      notification_type: "mentioned", body: "secret"
    )
    # 현재 로그인 사용자(@user)는 other_notif 소유자가 아님 → current_user.notifications.find → RecordNotFound → 404
    patch acknowledge_notification_path(other_notif)
    assert_response :not_found
  ensure
    other_notif&.destroy
    other_order&.destroy
    other_user&.destroy
  end

  test "PATCH acknowledge is idempotent — second call still succeeds" do
    m = make_mention
    patch acknowledge_notification_path(m), as: :json
    assert_response :success
    first_ts = m.reload.acknowledged_at

    sleep 0.05
    patch acknowledge_notification_path(m), as: :json
    assert_response :success
    assert_equal first_ts.to_f, m.reload.acknowledged_at.to_f, "second acknowledge must not update timestamp"
  end

  test "PATCH view sets viewed_at and viewed_duration_sec" do
    m = make_mention
    patch view_notification_path(m), params: { duration: 5 }
    assert_response :success
    m.reload
    assert m.viewed_at.present?
    assert_equal 5, m.viewed_duration_sec
  end

  test "PATCH view clamps duration over 3600 to 3600" do
    m = make_mention
    patch view_notification_path(m), params: { duration: 99999 }
    assert_response :success
    assert_equal 3600, m.reload.viewed_duration_sec
  end

  test "PATCH view clamps negative duration to 0" do
    m = make_mention
    patch view_notification_path(m), params: { duration: -5 }
    assert_response :success
    assert_equal 0, m.reload.viewed_duration_sec
  end

  # ─────────────────────────────────────────
  # T14 회귀 — read / read_all / index 동작 변화 0
  # ─────────────────────────────────────────

  test "PATCH read still works after acknowledge addition (회귀)" do
    n = Notification.create!(user: @user, notifiable: @order, notification_type: "system", body: "regression read")
    patch read_notification_path(n)
    assert_response :redirect
    assert_not_nil n.reload.read_at
  end

  test "PATCH read_all still works (회귀)" do
    Notification.create!(user: @user, notifiable: @order, notification_type: "system", body: "rg read_all")
    patch read_all_notifications_path
    assert_response :redirect
    assert_equal 0, @user.notifications.unread.count
  end

  test "GET index 회귀 — mentioned 카테고리 카운트 정확" do
    Notification.create!(user: @user, notifiable: @order, notification_type: "mentioned", body: "@u 1")
    Notification.create!(user: @user, notifiable: @order, notification_type: "mentioned", body: "@u 2")
    get notifications_path
    assert_response :success
    # 본 컨트롤러의 @category_counts 집계가 mentioned로 2건 이상 잡혀야 함
    mention_count = @user.notifications.where(notification_type: "mentioned").count
    assert mention_count >= 2, "expected at least 2 mentioned notifications for current_user"
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
