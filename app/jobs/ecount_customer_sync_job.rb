# frozen_string_literal: true

# eCountERP 거래처 동기화 백그라운드 Job
# Schedule: config/recurring.yml (매 시간 45분)
class EcountCustomerSyncJob < ApplicationJob
  queue_as :default

  def perform
    log = EcountSyncLog.create!(
      sync_type:  "customers",
      status:     :running,
      started_at: Time.current
    )

    result = EcountApi::CustomerSyncService.new.sync!(log)

    log.update!(
      status:        :completed,
      completed_at:  Time.current,
      error_details: result[:errors].to_json
    )

    Rails.logger.info "[EcountCustomerSyncJob] 완료: #{result[:success]}/#{result[:total]} (log ##{log.id})"
  rescue EcountApi::AuthError => e
    finish_failed(log, e)
    Rails.logger.error "[EcountCustomerSyncJob] 인증 실패: #{e.message}"
  rescue StandardError => e
    finish_failed(log, e)
    Rails.logger.error "[EcountCustomerSyncJob] 실패: #{e.class} — #{e.message}"
  end

  private

  def finish_failed(log, error)
    log&.update!(
      status:        :failed,
      completed_at:  Time.current,
      error_details: [ { error: error.message } ].to_json
    )
  end
end
