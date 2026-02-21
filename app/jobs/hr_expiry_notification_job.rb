# frozen_string_literal: true

# Sends expiry notifications for visas and employment contracts.
# Visa triggers: D-60, D-30, D-14
# Contract triggers: D-30, D-14
#
# Schedule: daily at 08:00 (see config/recurring.yml)
class HrExpiryNotificationJob < ApplicationJob
  queue_as :default

  VISA_TRIGGER_DAYS     = [60, 30, 14].freeze
  CONTRACT_TRIGGER_DAYS = [30, 14].freeze

  def perform
    today = Date.today

    VISA_TRIGGER_DAYS.each do |days_ahead|
      target_date = today + days_ahead.days
      visas = Visa.active.where(expiry_date: target_date).includes(employee: :user)
      visas.each do |visa|
        Rails.logger.warn "[HrExpiry] 비자 만료 D-#{days_ahead}: #{visa.employee.name} " \
                          "(#{visa.visa_type}/#{visa.issuing_country})"
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
      end
      Rails.logger.info "[HrExpiry] D-#{days_ahead} 계약 만료 대상: #{contracts.count}명"
    end
  end
end
