# frozen_string_literal: true

require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  def setup
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
    @notification.destroy if Notification.exists?(@notification.id)
    @order.destroy if Order.exists?(@order.id)
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

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
