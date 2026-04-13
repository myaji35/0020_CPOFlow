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
      max_fetch = 0  # 무제한 — 해당 기간 전체 수집
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

      # Idempotency 가드: 이미 동일 Gmail id로 Order가 있으면 스킵
      if Order.exists?(source_email_id: parsed[:id])
        Rails.logger.info "[EmailSyncJob] skip already-imported message #{parsed[:id]}"
        next
      end

      total_processed += 1

      # ── 1단계: RFQ 번호(발주번호) 유무 확인 ──
      # RFQ/PO 번호가 있으면 AI 판단 없이 무조건 견적성 메일로 수신
      ref_no = Gmail::ReferenceNumberExtractor.extract(
        parsed[:subject].to_s, parsed[:body].to_s
      )
      has_rfq_number = ref_no.present?

      # ── 2단계: AI 분류 ──
      # RFQ 번호가 있으면 AI 분류 스킵 (비용 절감 + 확실한 건적)
      # RFQ 번호가 없으면 AI 파이프라인으로 판정
      detection = begin
        Gmail::RfqDetectorService.new(parsed).detect
      rescue => e
        Rails.logger.warn "[EmailSyncJob] RFQ detection failed: #{e.message}"
        { rfq_verdict: :pending, score: 0, confidence: "none", is_rfq: false }
      end

      # v2 ClassificationOrchestrator (Active Mode)
      orchestrator = nil
      v2_result = nil
      unless has_rfq_number
        if Gmail::CostGuard.exceeded?
          Gmail::CostGuard.warn_once!
        else
          orchestrator = Gmail::ClassificationOrchestrator.new(parsed)
          v2_result = begin
            orchestrator.classify
          rescue => e
            Rails.logger.warn "[EmailSyncJob] v2 classify failed: #{e.class} — #{e.message}"
            nil
          end
        end
      end
      v2_log_id = v2_result ? orchestrator&.last_log_id : nil

      # ── 3단계: 수신 여부 결정 ──
      # (a) RFQ 번호 있음 → 무조건 수신 (confirmed)
      # (b) AI 판정 confirmed/uncertain → 수신 (모호한 건도 수신 — recall 우선)
      # (c) AI 판정 excluded → 수신 안 함 (확실히 비견적 메일만 제외)
      should_import = if has_rfq_number
        true
      else
        ai_verdict = v2_result&.verdict || detection[:rfq_verdict]
        ai_verdict != :excluded
      end

      unless should_import
        Rails.logger.info "[EmailSyncJob] skip non-RFQ email: #{parsed[:subject]} (verdict=excluded)"
        next
      end

      order = Gmail::EmailToOrderService.new(
        account, parsed, detection,
        v2_result: v2_result, v2_log_id: v2_log_id,
        has_rfq_number: has_rfq_number
      ).create_order!

      if order
        Gmail::EmailAttachmentExtractorService.new(svc, msg, order).extract_and_attach!
        new_rfq_count += 1 if has_rfq_number || detection[:is_rfq]

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
