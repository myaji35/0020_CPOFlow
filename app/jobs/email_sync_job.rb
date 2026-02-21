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
    accounts = account_id ? [EmailAccount.find(account_id)] : connected_accounts

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

    Rails.logger.info "[EmailSyncJob] Syncing account: #{account.email}"

    svc = Gmail::GmailService.new(account)

    # Fetch unread messages (or all recent if first sync)
    query = account.last_synced_at ? "is:unread after:#{account.last_synced_at.to_i}" : "is:unread"
    messages = svc.fetch_recent_messages(max: 50, query: query)

    new_rfq_count   = 0
    total_processed = 0

    messages.each do |msg|
      parsed = svc.parse_message(msg)
      next unless parsed

      total_processed += 1

      detection = Gmail::RfqDetectorService.new(parsed).detect
      next unless detection[:is_rfq]

      order = Gmail::EmailToOrderService.new(account, parsed, detection).create_order!
      new_rfq_count += 1 if order
    end

    account.mark_synced!

    Rails.logger.info "[EmailSyncJob] #{account.email}: processed=#{total_processed}, new_rfqs=#{new_rfq_count}"
  end
end
