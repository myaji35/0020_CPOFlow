# frozen_string_literal: true

require "test_helper"

# ISS-354 Phase 2 Wave 4 — T15
# OrdersController mention 엔드포인트 (sender_hover, remind_all, remind_one)
class OrdersControllerMentionTest < ActionDispatch::IntegrationTest
  setup do
    I18n.locale = :ko
    suffix = SecureRandom.hex(3)
    @sender = User.find_or_create_by!(email: "ctrl_sender_#{suffix}@test.com") do |u|
      u.password = "password123"; u.role = :member; u.name = "CSender_#{suffix}"
    end
    @receiver = User.find_or_create_by!(email: "ctrl_receiver_#{suffix}@test.com") do |u|
      u.password = "password123"; u.role = :member; u.name = "CReceiver_#{suffix}"
    end
    @other = User.find_or_create_by!(email: "ctrl_other_#{suffix}@test.com") do |u|
      u.password = "password123"; u.role = :member; u.name = "COther_#{suffix}"
    end
    @order = Order.create!(title: "ctrl test #{suffix}", customer_name: "Cust",
                           status: :new_rfq, user: @sender)
    @notif = Notification.create!(user: @receiver, notifiable: @order,
                                  notification_type: "mentioned",
                                  intent_level: 1, sent_by_user_id: @sender.id,
                                  title: "@@", body: "확인 부탁")
  end

  teardown do
    I18n.locale = I18n.default_locale
    Notification.where(notifiable: @order).destroy_all if @order
    @order&.reload&.destroy if @order && Order.exists?(@order.id)
    @sender&.destroy
    @receiver&.destroy
    @other&.destroy
  end

  # === GET mention_sender_hover ===

  test "GET mention_sender_hover — 발신자가 보면 partial 렌더" do
    login_as(@sender)
    get mention_sender_hover_order_path(@order)
    assert_response :success
    assert_match(/sender-hover-#{@order.id}/, response.body)
  end

  test "GET mention_sender_hover — 비발신자(타사용자)는 no_content (B3 격리)" do
    login_as(@other)
    get mention_sender_hover_order_path(@order)
    assert_response :no_content
  end

  # === POST mention_remind_all ===

  test "POST mention_remind_all — 발신자가 보내면 reminded_at 기록된 새 알림 생성" do
    login_as(@sender)
    assert_difference -> { Notification.where(notifiable: @order).count }, +1 do
      post mention_remind_all_order_path(@order)
    end
    assert_response :success
    new_notif = Notification.where(notifiable: @order).order(:created_at).last
    assert_not_nil new_notif.reminded_at, "리마인드 알림은 reminded_at 기록"
    assert_equal @sender.id, new_notif.sent_by_user_id
    assert_equal @receiver.id, new_notif.user_id
  end

  test "POST mention_remind_all — cooldown 활성 시 새 알림 미생성" do
    @notif.update_columns(reminded_at: 1.hour.ago)
    login_as(@sender)
    assert_no_difference -> { Notification.where(notifiable: @order).count } do
      post mention_remind_all_order_path(@order)
    end
  end

  test "POST mention_remind_all — 비발신자는 forbidden" do
    login_as(@other)
    post mention_remind_all_order_path(@order)
    assert_response :forbidden
  end

  # === POST mention_remind_one ===

  test "POST mention_remind_one — 정상 (발신자, receiver, no cooldown)" do
    login_as(@sender)
    assert_difference -> { Notification.where(notifiable: @order).count }, +1 do
      post mention_remind_one_order_path(@order, user_id: @receiver.id)
    end
    assert_response :success
  end

  test "POST mention_remind_one — cooldown 활성 시 forbidden" do
    @notif.update_columns(reminded_at: 1.hour.ago)
    login_as(@sender)
    post mention_remind_one_order_path(@order, user_id: @receiver.id)
    assert_response :forbidden
  end

  test "POST mention_remind_one — 발신자가 멘션한 적 없는 receiver면 forbidden" do
    login_as(@sender)
    post mention_remind_one_order_path(@order, user_id: @other.id)
    assert_response :forbidden
  end

  private

  # 기존 orders_controller_test.rb / kanban_controller_test.rb 와 동일한 패턴
  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
