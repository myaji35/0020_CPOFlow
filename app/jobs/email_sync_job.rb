# frozen_string_literal: true

# Fetches new Gmail messages for all connected accounts,
# runs RFQ detection, and auto-creates Orders for detected RFQs.
#
# Scheduled via Solid Queue recurring job (see config/recurring.yml)
# Manual trigger: EmailSyncJob.perform_later
# Per-account:   EmailSyncJob.perform_later(account_id: 42)
class EmailSyncJob < ApplicationJob
  queue_as :default

  # Retry up to 3 times on transient errors; wait 5 minutes between attempts
  retry_on StandardError, wait: 5.minutes, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(account_id: nil)
    accounts = account_id ? [ EmailAccount.find(account_id) ] : connected_accounts

    accounts.each do |account|
      sync_account(account)
    rescue => e
      Rails.logger.error "[EmailSyncJob] Error syncing #{account.email}: #{e.class} — #{e.message}"
    end
  end

  private

  def connected_accounts
    EmailAccount.where(connected: true).includes(:user)
  end

  def sync_account(account)
    return if account.synced_recently?

    unless account.ready?
      Rails.logger.warn "[EmailSyncJob] #{account.email}: skipped — token expired and no refresh_token. Re-auth required."
      return
    end

    Rails.logger.info "[EmailSyncJob] Syncing account: #{account.email}"

    svc = Gmail::GmailService.new(account)

    # Fetch messages: 첫 동기화는 최근 90일치 전체, 이후는 마지막 동기화 이후 신규
    if account.last_synced_at.nil?
      # 초회 동기화: 최근 90일치 전체 (read/unread 모두)
      after_ts = 90.days.ago.to_i
      query = "after:#{after_ts}"
      max_fetch = 100
    else
      # 이후 동기화: 마지막 동기화 이후 신규 메일
      query = "after:#{account.last_synced_at.to_i}"
      max_fetch = 50
    end
    messages = svc.fetch_recent_messages(max: max_fetch, query: query)

    new_rfq_count   = 0
    total_processed = 0

    messages.each do |msg|
      parsed = svc.parse_message(msg)
      next unless parsed

      total_processed += 1

      detection = Gmail::RfqDetectorService.new(parsed).detect

      # RFQ 여부와 무관하게 모든 수신 메일을 Inbox에 저장
      order = Gmail::EmailToOrderService.new(account, parsed, detection).create_order!

      if order
        Gmail::EmailAttachmentExtractorService.new(svc, msg, order).extract_and_attach!
        new_rfq_count += 1 if detection[:is_rfq]
      end
    end

    account.mark_synced!

    Rails.logger.info "[EmailSyncJob] #{account.email}: processed=#{total_processed}, new_rfqs=#{new_rfq_count}"
  end
end
