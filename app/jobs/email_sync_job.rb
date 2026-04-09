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

      # ISS-056 Idempotency 가드: 이미 동일 Gmail id로 Order가 있으면
      # Orchestrator/Detector 재호출 자체를 skip (재시도 시 로그 중복 생성 방지)
      if Order.exists?(source_email_id: parsed[:id])
        Rails.logger.info "[EmailSyncJob] skip already-imported message #{parsed[:id]}"
        next
      end

      total_processed += 1

      # --- 방식 2 (백그라운드 안전망) — 7일 Shadow 기간 유지 ---
      # AI 판정은 추천 점수 계산용으로만 실행 (분류/필터링 안 함)
      detection = begin
        Gmail::RfqDetectorService.new(parsed).detect
      rescue => e
        Rails.logger.warn "[EmailSyncJob] RFQ detection failed: #{e.message}"
        { rfq_verdict: :pending, score: 0, confidence: "none", is_rfq: false }
      end

      # --- v2 ClassificationOrchestrator (Shadow Mode 옵션 B, ISS-053) ---
      # v2 결과는 Order 메트릭 필드 + classification_logs에 기록되지만
      # rfq_status 자동 할당은 Shadow 종료 후(Phase G cutover)에만.
      # excluded 판정도 rfq_pending으로 저장 → would_exclude=true 로그로만 추적.
      # ISS-056: orchestrator 인스턴스를 유지하여 last_log_id를 EmailToOrderService로 전달
      # ISS-058: CostGuard 진입 가드 — 일 비용 임계 초과 시 v2 skip (방식 2는 유지)
      orchestrator = nil
      v2_result = nil
      if Gmail::CostGuard.exceeded?
        Gmail::CostGuard.warn_once!
        # v2 skip — 방식 2 백그라운드는 이미 위에서 실행되었으므로 안전
      else
        orchestrator = Gmail::ClassificationOrchestrator.new(parsed)
        v2_result = begin
          orchestrator.classify
        rescue => e
          Rails.logger.warn "[EmailSyncJob] v2 classify failed: #{e.class} — #{e.message}"
          nil
        end
      end
      v2_log_id = v2_result ? orchestrator&.last_log_id : nil

      # 모든 이메일을 Inbox에 저장 (v2 excluded 여부 무관)
      order = Gmail::EmailToOrderService.new(
        account, parsed, detection, v2_result: v2_result, v2_log_id: v2_log_id
      ).create_order!

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
