# frozen_string_literal: true

# 납기 D-7, D-3, D-0 자동 알림 발송 Job
# Solid Queue 스케줄러로 매일 오전 9시 실행 권장
class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  DUE_DAYS = [7, 3, 0].freeze

  def perform
    DUE_DAYS.each do |days|
      target_date = Date.today + days.days
      orders = Order.where(due_date: target_date)
                    .where.not(status: :delivered)
                    .includes(:assignees, :client)

      orders.each do |order|
        notify_order(order, days)
      end
    end

    Rails.logger.info "[NotificationDeliveryJob] Completed at #{Time.current}"
  end

  private

  def notify_order(order, days)
    title = days == 0 ? "⚠️ 오늘 납기!" : "납기 D-#{days}: #{order.title}"
    body  = build_body(order, days)

    order.assignees.each do |user|
      next if already_notified_today?(order, user, days)

      Notification.create!(
        user:              user,
        notifiable:        order,
        title:             title,
        body:              body,
        notification_type: "due_date"
      )
    end

    # Google Chat 발송 (한 번만)
    GoogleChatService.notify(body, order: order, title: title)
  end

  def build_body(order, days)
    client_name = order.client&.name || order.customer_name
    if days == 0
      "오늘 납기입니다! #{client_name} / #{order.title}"
    else
      "#{days}일 후 납기 예정입니다. #{client_name} / #{order.title}"
    end
  end

  def already_notified_today?(order, user, days)
    Notification.where(
      user:              user,
      notifiable:        order,
      notification_type: "due_date"
    ).where("created_at >= ?", Date.today.beginning_of_day).exists?
  end
end
