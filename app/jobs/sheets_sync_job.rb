# frozen_string_literal: true

class SheetsSyncJob < ApplicationJob
  queue_as :default

  def perform
    svc = Sheets::SheetsService.new
    log = svc.sync_all

    if log.mock?
      Rails.logger.info "[SheetsSyncJob] Mock sync complete — #{log.total_count} records counted"
    else
      Rails.logger.info "[SheetsSyncJob] Sync complete — #{log.total_count} records pushed"
    end
  rescue => e
    Rails.logger.error "[SheetsSyncJob] Failed: #{e.message}"
  end
end
