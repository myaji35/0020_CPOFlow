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

  # since_date: Date 또는 Time — 이 날짜 이후 메일만 가져옴 (백필용)
  # force: true — synced_recently? 체크를 무시하고 강제 실행 (백필용)
  def perform(account_id: nil, since_date: nil, force: false)
    accounts = account_id ? [ EmailAccount.find(account_id) ] : connected_accounts

    accounts.each do |account|
      sync_account(account, since_date: since_date, force: force)
    rescue => e
      Rails.logger.error "[EmailSyncJob] Error syncing #{account.email}: #{e.class} — #{e.message}"
    end
  end

  private

  def connected_accounts
    EmailAccount.where(connected: true).includes(:user)
  end

  def sync_account(account, since_date: nil, force: false)
    return if !force && account.synced_recently?

    unless account.ready?
      Rails.logger.warn "[EmailSyncJob] #{account.email}: skipped — token expired and no refresh_token. Re-auth required."
      return
    end

    Rails.logger.info "[EmailSyncJob] Syncing account: #{account.email}#{since_date ? " (since: #{since_date})" : ""}"

    svc = Gmail::GmailService.new(account)

    # Fetch messages: 우선순위 — since_date 지정 > 마지막 동기화 이후 > 초회 90일
    # 프로모션/소셜/스팸 카테고리 제외 — 기본 받은편지함(PRIMARY)만 동기화
    if since_date.present?
      # 백필 모드: 지정 날짜 이후 전체 가져오기
      after_ts = since_date.to_time.to_i
      query = "after:#{after_ts} category:primary"
      max_fetch = 500
    elsif account.last_synced_at.nil?
      # 초회 동기화: 최근 90일치 전체 (read/unread 모두)
      after_ts = 90.days.ago.to_i
      query = "after:#{after_ts} category:primary"
      max_fetch = 100
    else
      # 이후 동기화: 마지막 동기화 이후 신규 메일
      query = "after:#{account.last_synced_at.to_i} category:primary"
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

      # confirmed 판정만 Order로 생성 — uncertain/excluded는 건너뜀
      unless detection[:rfq_verdict] == :confirmed
        Rails.logger.debug "[EmailSyncJob] Skipped #{detection[:rfq_verdict]} email (score=#{detection[:score]}): #{parsed[:subject]}"
        next
      end

      # RFQ confirmed 이메일만 Inbox에 저장
      order = Gmail::EmailToOrderService.new(account, parsed, detection).create_order!

      if order
        Gmail::EmailAttachmentExtractorService.new(svc, msg, order).extract_and_attach!
        new_rfq_count += 1 if detection[:is_rfq]

        # Ariba 링크가 포함된 이메일이면 자동으로 문서 수집 잡 큐잉
        if Sap::AribaScraperService.extract_ariba_links(order).any?
          AribaFetchJob.perform_later(order_id: order.id)
          Rails.logger.info "[EmailSyncJob] Order##{order.id}: Ariba 링크 감지 → AribaFetchJob 큐잉"
        end
      end
    end

    account.mark_synced!

    Rails.logger.info "[EmailSyncJob] #{account.email}: processed=#{total_processed}, new_rfqs=#{new_rfq_count}"
  end
end
