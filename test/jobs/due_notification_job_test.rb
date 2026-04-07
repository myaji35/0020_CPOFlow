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

  test "perform — GoogleChatService stub하고 실행 성공" do
    # GoogleChatService의 notify를 no-op으로 대체
    notify_stub = ->(*, **) { nil }
    GoogleChatService.define_singleton_method(:notify, notify_stub)
    assert_nothing_raised do
      DueNotificationJob.new.perform
    end
  ensure
    # 원래 메서드 복원 (singleton_method 제거)
    GoogleChatService.singleton_class.send(:remove_method, :notify) rescue nil
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
