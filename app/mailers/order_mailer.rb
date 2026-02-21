# frozen_string_literal: true

class OrderMailer < ApplicationMailer
  # Due date reminder email: D-14, D-7, D-3, D-0
  def due_reminder(order, user, days_remaining)
    @order          = order
    @user           = user
    @days_remaining = days_remaining
    @urgency        = urgency_label(days_remaining)

    mail(
      to:      user.email,
      subject: "[CPOFlow] #{@urgency} — #{order.title} due #{days_label(days_remaining)}"
    )
  end

  private

  def urgency_label(days)
    case days
    when 0    then "OVERDUE TODAY"
    when 1..3 then "URGENT"
    when 4..7 then "Action Required"
    else           "Reminder"
    end
  end

  def days_label(days)
    case days
    when 0 then "today"
    when 1 then "tomorrow"
    else        "in #{days} days"
    end
  end
end
