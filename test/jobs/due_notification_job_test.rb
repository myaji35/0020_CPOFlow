# frozen_string_literal: true

require "test_helper"

class DueNotificationJobTest < ActiveJob::TestCase
  def setup
    @user = User.find_or_create_by(email: "due_notif_job_test@example.com") do |u|
      u.name = "DueNotifJob Test"; u.password = "password123"; u.role = :member
    end
    @order_today = Order.create!(
      title: "Today Due Order",
      customer_name: "Client A",
      user: @user,
      status: :new_rfq,
      due_date: Date.today
    )
    @order_7days = Order.create!(
      title: "7 Days Order",
      customer_name: "Client B",
      user: @user,
      status: :new_rfq,
      due_date: Date.today + 7.days
    )
  end

  def teardown
    @order_today.destroy if Order.exists?(@order_today.id)
    @order_7days.destroy if Order.exists?(@order_7days.id)
  end

  test "perform — GoogleChatService 호출 에러 없이 실행 성공" do
    # GoogleChatService.notify는 webhook URL 미설정 시 false 반환 (API 호출 없음)
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
    assert_nothing_raised do
      DueNotificationJob.new.perform
    end
  end

  test "TRIGGER_DAYS — 14, 7, 3, 0 포함" do
    assert_includes DueNotificationJob::TRIGGER_DAYS, 0
    assert_includes DueNotificationJob::TRIGGER_DAYS, 7
    assert_includes DueNotificationJob::TRIGGER_DAYS, 14
    assert_includes DueNotificationJob::TRIGGER_DAYS, 3
  end

  test "perform enqueue 가능" do
    assert_enqueued_with(job: DueNotificationJob) do
      DueNotificationJob.perform_later
    end
  end
end
