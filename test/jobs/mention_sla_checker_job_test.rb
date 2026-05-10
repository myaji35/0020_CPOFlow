# frozen_string_literal: true

require "test_helper"

# ISS-354 Phase 2 Wave 4 — T14
# MentionSlaCheckerJob 25h 윈도우 + freeze_time 검증
class MentionSlaCheckerJobTest < ActiveJob::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    I18n.locale = :ko
    suffix = SecureRandom.hex(3)
    @sender = User.find_or_create_by!(email: "sla_sender_#{suffix}@test.com") do |u|
      u.password = "password123"; u.role = :member; u.name = "SLA발신_#{suffix}"
    end
    @receiver = User.find_or_create_by!(email: "sla_receiver_#{suffix}@test.com") do |u|
      u.password = "password123"; u.role = :member; u.name = "SLA수신_#{suffix}"
    end
    @order = Order.create!(title: "SLA test #{suffix}", customer_name: "Cust",
                           status: :new_rfq, user: @sender)
    Notification.where(notifiable: @order).destroy_all
  end

  teardown do
    I18n.locale = I18n.default_locale
    travel_back
    Notification.where(notifiable: @order).destroy_all if @order
    @order&.reload&.destroy if @order && Order.exists?(@order.id)
    @sender&.destroy
    @receiver&.destroy
  end

  test "perform — 새로 SLA 초과된 멘션이 카운터 캐시 갱신을 트리거한다" do
    # 2시간 전 @@@ 멘션 → SLA 1시간 → 이미 1시간 초과
    travel_to Time.current - 2.hours do
      Notification.create!(user: @receiver, notifiable: @order, notification_type: "mentioned",
                           intent_level: 2, sent_by_user_id: @sender.id, title: "@@@", body: "응답 필수")
    end
    # 의도적 stale state — recompute 누락된 상황 시뮬레이션
    @order.update_columns(mention_sla_overdue_count: 0, mention_worst_state: "unread")

    MentionSlaCheckerJob.new.perform

    @order.reload
    assert_equal 1, @order.mention_sla_overdue_count, "SLA 초과 카운트 갱신"
    assert_equal "sla_overdue", @order.mention_worst_state, "worst_state SLA 우선"
  end

  test "perform — 25h 이상 stale 멘션은 윈도우 밖 (B4 결정)" do
    # 30시간 전 @@@ — sla_due_at는 29시간 전 → 25h 윈도우 초과 → 무시
    travel_to Time.current - 30.hours do
      Notification.create!(user: @receiver, notifiable: @order, notification_type: "mentioned",
                           intent_level: 2, sent_by_user_id: @sender.id, title: "@@@", body: "x")
    end
    @order.update_columns(mention_sla_overdue_count: 0)

    MentionSlaCheckerJob.new.perform

    @order.reload
    # 30h 전 멘션의 sla_due_at은 29h 전 → "25h 이상 오래된 SLA"는 윈도우 밖 → recompute 발화 안 됨
    assert_equal 0, @order.mention_sla_overdue_count, "윈도우 밖 멘션은 stale 유지"
  end

  test "perform — 이미 acknowledged된 멘션은 무시한다" do
    travel_to Time.current - 2.hours do
      n = Notification.create!(user: @receiver, notifiable: @order, notification_type: "mentioned",
                               intent_level: 2, sent_by_user_id: @sender.id, title: "@@@", body: "x")
      n.update_columns(acknowledged_at: Time.current)
    end
    @order.update_columns(mention_sla_overdue_count: 0)

    MentionSlaCheckerJob.new.perform

    @order.reload
    assert_equal 0, @order.mention_sla_overdue_count, "ack된 멘션은 SLA 카운트 제외"
  end

  test "perform — 멘션이 아닌 알림은 무시한다" do
    Notification.create!(user: @receiver, notifiable: @order, notification_type: "due_date",
                         title: "납기 D-1", body: "납기 임박")
    assert_nothing_raised { MentionSlaCheckerJob.new.perform }
  end

  test "perform — 영향받는 Order에 raise 없이 완료된다 (broadcast 안전)" do
    travel_to Time.current - 2.hours do
      Notification.create!(user: @receiver, notifiable: @order, notification_type: "mentioned",
                           intent_level: 2, sent_by_user_id: @sender.id, title: "@@@", body: "x")
    end
    # broadcast_replace_to는 ActionCable 어댑터가 test에서 noop이므로 raise 없음 검증
    assert_nothing_raised { MentionSlaCheckerJob.new.perform }
  end
end
