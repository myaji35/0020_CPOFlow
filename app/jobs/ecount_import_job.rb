# frozen_string_literal: true

# eCountERP 데이터 이관을 비동기로 처리하는 Solid Queue Job
class EcountImportJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 2.minutes, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(import_log_id)
    log = ImportLog.find(import_log_id)

    # 이미 처리 중이거나 완료된 경우 스킵
    return if log.processing? || log.completed?

    log.update!(status: :processing)
    Ecount::EcountImportService.new(log).run!
  rescue => e
    log&.update!(status: :failed,
                 error_details: [{ row: 0, error: "#{e.class}: #{e.message}" }].to_json,
                 completed_at: Time.current)
    raise
  end
end
