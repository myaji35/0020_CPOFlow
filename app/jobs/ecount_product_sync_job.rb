# frozen_string_literal: true

# eCountERP 품목 동기화 백그라운드 Job
# Schedule: config/recurring.yml (매 시간 30분)
class EcountProductSyncJob < ApplicationJob
  queue_as :default

  def perform
    log = EcountSyncLog.create!(
      sync_type:  "products",
      status:     :running,
      started_at: Time.current
    )

    result = EcountApi::ProductSyncService.new.sync!(log)

    log.update!(
      status:        :completed,
      completed_at:  Time.current,
      error_details: result[:errors].to_json
    )

    Rails.logger.info "[EcountProductSyncJob] 완료: #{result[:success]}/#{result[:total]} (log ##{log.id})"
  rescue EcountApi::AuthError => e
    finish_failed(log, e)
    Rails.logger.error "[EcountProductSyncJob] 인증 실패: #{e.message}"
  rescue StandardError => e
    finish_failed(log, e)
    Rails.logger.error "[EcountProductSyncJob] 실패: #{e.class} — #{e.message}"
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
