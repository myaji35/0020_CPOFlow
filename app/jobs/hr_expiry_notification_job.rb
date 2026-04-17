# frozen_string_literal: true

# Sends expiry notifications for visas and employment contracts.
# Visa triggers: D-60, D-30, D-14
# Contract triggers: D-30, D-14
#
# Schedule: daily at 08:00 (see config/recurring.yml)
class HrExpiryNotificationJob < ApplicationJob
  queue_as :default

  VISA_TRIGGER_DAYS     = [ 60, 30, 14 ].freeze
  CONTRACT_TRIGGER_DAYS = [ 30, 14 ].freeze

  def perform
    today = Date.today

    managers = User.where(role: %w[manager admin])

    VISA_TRIGGER_DAYS.each do |days_ahead|
      target_date = today + days_ahead.days
      visas = Visa.active.where(expiry_date: target_date).includes(employee: :user)
      visas.each do |visa|
        Rails.logger.warn "[HrExpiry] 비자 만료 D-#{days_ahead}: #{visa.employee.name} " \
                          "(#{visa.visa_type}/#{visa.issuing_country})"

        # ISS-221: D-60 도달 시 renewal 자동 시작 (미시작 상태인 경우만)
        if days_ahead == 60 && visa.renewal_started_at.nil?
          visa.update_columns(
            renewal_started_at: Time.current,
            renewal_status:     "in_progress",
            renewal_note:       "D-60 자동 시작 (HrExpiryNotificationJob)"
          )
          Rails.logger.info "[HrExpiry] 비자 ##{visa.id} 갱신 자동 시작 (D-60)"
        end

        key = "visa_#{visa.id}_d#{days_ahead}"
        managers.each do |manager|
          unless Notification.where(user: manager, notification_type: key).exists?
            Notification.create!(
              user:              manager,
              notifiable:        visa.employee,
              notification_type: key,
              title:             "비자 만료 D-#{days_ahead}: #{visa.employee.name}",
              body:              "#{visa.visa_type} (#{visa.issuing_country}) — #{visa.expiry_date&.strftime('%Y-%m-%d')} 만료" +
                                 (days_ahead == 60 ? " · 갱신 프로세스 자동 시작됨" : "")
            )
          end
        end
      end
      Rails.logger.info "[HrExpiry] D-#{days_ahead} 비자 만료 대상: #{visas.count}명"
    end

    CONTRACT_TRIGGER_DAYS.each do |days_ahead|
      target_date = today + days_ahead.days
      contracts = EmploymentContract.active
                                    .where(end_date: target_date)
                                    .includes(:employee)
      contracts.each do |contract|
        Rails.logger.warn "[HrExpiry] 계약 만료 D-#{days_ahead}: #{contract.employee.name}"
        key = "contract_#{contract.id}_d#{days_ahead}"
        managers.each do |manager|
          unless Notification.where(user: manager, notification_type: key).exists?
            Notification.create!(
              user:              manager,
              notifiable:        contract.employee,
              notification_type: key,
              title:             "계약 만료 D-#{days_ahead}: #{contract.employee.name}",
              body:              "고용계약 #{contract.end_date&.strftime('%Y-%m-%d')} 만료 예정"
            )
          end
        end
      end
      Rails.logger.info "[HrExpiry] D-#{days_ahead} 계약 만료 대상: #{contracts.count}명"
    end
  end
end
