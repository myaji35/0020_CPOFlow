# frozen_string_literal: true

# ISS-039: 매일 실행 — urgent/high + 마감일 경과 + 담당자 미배정 = critical Order에
# 대해 admin/manager(branch 일치)에게 Notification 생성.
# 멱등성: 같은 Order + 같은 날 이미 escalation 알림이 있으면 skip.
class OverdueEscalationJob < ApplicationJob
  queue_as :default

  ESCALATION_TYPE = "overdue_unassigned_escalation"

  def perform
    Order.critical.find_each do |order|
      escalate(order)
    end
  end

  private

  def escalate(order)
    recipients_for(order).each do |user|
      next if already_escalated_today?(order, user)

      days_overdue = (Date.today - order.due_date).to_i
      Notification.create!(
        user:              user,
        notifiable:        order,
        notification_type: ESCALATION_TYPE,
        title:             "긴급: 담당자 미배정 발주 #{days_overdue}일 경과",
        body:              "#{order.title} — 마감 #{days_overdue}일 경과, 담당자 미배정 상태입니다. 즉시 조치 바랍니다."
      )
    rescue => e
      Rails.logger.error "[OverdueEscalationJob] Notification 생성 오류 order##{order.id} user##{user.id}: #{e.message}"
    end
  end

  def already_escalated_today?(order, user)
    Notification.where(
      user:              user,
      notifiable:        order,
      notification_type: ESCALATION_TYPE
    ).where(created_at: Time.current.beginning_of_day..).exists?
  end

  def recipients_for(order)
    branch = order.user&.branch
    scope = User.where(role: [ :admin, :manager ])
    scope = scope.where(branch: branch) if branch.present?
    scope.distinct
  end
end
