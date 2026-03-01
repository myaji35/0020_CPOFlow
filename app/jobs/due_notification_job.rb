# frozen_string_literal: true

# 납기일 임박 알림 Job — 이메일 + Google Chat + 인앱 Notification
# 트리거: D-14, D-7, D-3, D-0
# 스케줄: 매일 오전 7:00 (config/recurring.yml)
class DueNotificationJob < ApplicationJob
  queue_as :default

  TRIGGER_DAYS = [ 14, 7, 3, 0 ].freeze

  def perform
    today = Date.today

    TRIGGER_DAYS.each do |days_ahead|
      target_date = today + days_ahead.days
      orders = due_orders_on(target_date)

      orders.each do |order|
        notify_order(order, days_ahead)
      end

      Rails.logger.info "[DueNotificationJob] D-#{days_ahead}: #{orders.count}건 처리"
    end
  end

  private

  def due_orders_on(date)
    Order.where(due_date: date)
         .where.not(status: :delivered)
         .includes(:assignees, :client)
  end

  def notify_order(order, days_ahead)
    title = build_title(days_ahead, order)
    body  = build_body(order, days_ahead)

    # 1) 인앱 Notification (담당자별, 중복 방지) — Employee에 연결된 User에게 발송
    order.assignees.each do |employee|
      linked_user = employee.user
      next unless linked_user
      next if already_notified_today?(order, linked_user, days_ahead)

      Notification.create!(
        user:              linked_user,
        notifiable:        order,
        title:             title,
        body:              body,
        notification_type: "due_date_d#{days_ahead}"
      )
    rescue => e
      Rails.logger.error "[DueNotificationJob] Notification 생성 오류 order##{order.id}: #{e.message}"
    end

    # 2) Google Chat (오더당 1회)
    return if chat_already_sent_today?(order, days_ahead)

    GoogleChatService.notify(body, order: order, title: title, days_ahead: days_ahead)
  rescue => e
    Rails.logger.error "[DueNotificationJob] Google Chat 오류 order##{order.id}: #{e.message}"
  end

  def build_title(days_ahead, order)
    case days_ahead
    when 0  then "오늘 납기! — #{order.title.truncate(30)}"
    when 3  then "납기 D-3 긴급 — #{order.title.truncate(30)}"
    when 7  then "납기 D-7 주의 — #{order.title.truncate(30)}"
    when 14 then "납기 D-14 예고 — #{order.title.truncate(30)}"
    else         "납기 알림 — #{order.title.truncate(30)}"
    end
  end

  def build_body(order, days_ahead)
    client_name = order.client&.name || order.customer_name
    case days_ahead
    when 0  then "오늘 납기입니다! #{client_name} / #{order.title}"
    else         "#{days_ahead}일 후 납기 예정입니다. #{client_name} / #{order.title}"
    end
  end

  def already_notified_today?(order, user, days_ahead)
    Notification.where(
      user:              user,
      notifiable:        order,
      notification_type: "due_date_d#{days_ahead}"
    ).where(created_at: Time.current.beginning_of_day..).exists?
  end

  def chat_already_sent_today?(order, days_ahead)
    # 인앱 알림 기준으로 오늘 이미 발송됐으면 Chat도 skip
    Notification.where(
      notifiable:        order,
      notification_type: "due_date_d#{days_ahead}"
    ).where(created_at: Time.current.beginning_of_day..).exists?
  end
end
