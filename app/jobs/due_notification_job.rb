# frozen_string_literal: true

# Sends due-date reminder emails for orders approaching their deadline.
# Triggers: D-14, D-7, D-3, D-0 (due date day)
#
# Schedule: daily at 07:00 (see config/recurring.yml)
class DueNotificationJob < ApplicationJob
  queue_as :default

  TRIGGER_DAYS = [14, 7, 3, 0].freeze

  def perform
    today = Date.today

    TRIGGER_DAYS.each do |days_ahead|
      target_date = today + days_ahead.days
      orders = due_orders_on(target_date)

      orders.each do |order|
        order.assignees.each do |user|
          OrderMailer.due_reminder(order, user, days_ahead).deliver_later
        rescue => e
          Rails.logger.error "[DueNotificationJob] Mailer error for order ##{order.id}: #{e.message}"
        end
      end

      Rails.logger.info "[DueNotificationJob] D-#{days_ahead}: #{orders.count} orders notified"
    end
  end

  private

  def due_orders_on(date)
    Order.where(due_date: date)
         .where.not(status: :delivered)
         .includes(:assignees)
  end
end
