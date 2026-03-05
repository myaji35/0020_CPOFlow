# frozen_string_literal: true

# Gmail 백필 태스크: 특정 날짜 이후의 이메일을 일괄 동기화하여 inbox에 추가
#
# Usage:
#   bin/rails gmail:backfill_since[2025-10-01]
#   bin/rails gmail:backfill_since[2025-10-01,42]   # 특정 account_id
#
# 주의: Gmail API 할당량 보호를 위해 메시지 간 0.1초 딜레이 적용
namespace :gmail do
  desc "2025-10-01 이후 이메일을 Gmail에서 읽어 inbox에 추가 (RFQ confirmed만)"
  task :backfill_since, [ :since_date, :account_id ] => :environment do |_, args|
    since_date_str = args[:since_date].presence || "2025-10-01"
    account_id     = args[:account_id].presence&.to_i

    begin
      since_date = Date.parse(since_date_str)
    rescue Date::Error
      puts "[GmailBackfill] 날짜 형식 오류: #{since_date_str} (YYYY-MM-DD 형식 사용)"
      exit 1
    end

    # connected: false여도 refresh_token이 있으면 백필 가능 (토큰 갱신 후 진행)
    accounts = if account_id
      [ EmailAccount.find(account_id) ]
    else
      EmailAccount.where("connected = ? OR gmail_refresh_token_ciphertext IS NOT NULL", true).includes(:user)
    end

    if accounts.empty?
      puts "[GmailBackfill] Gmail 계정 없음. Settings > Gmail 연동 확인 필요."
      exit 1
    end

    puts "[GmailBackfill] #{since_date} 이후 메일 백필 시작 (계정 #{accounts.size}개)"
    total_new    = 0
    total_skipped = 0

    accounts.each do |account|
      puts "[GmailBackfill] 계정: #{account.email}"

      # connected: false여도 refresh_token이 있으면 계속 진행 (토큰 갱신 시도)
      unless account.gmail_refresh_token.present? || account.gmail_access_token.present?
        puts "[GmailBackfill]   → access/refresh 토큰 없음 — Settings에서 Gmail 재인증 필요"
        next
      end

      # connected: false인 경우 임시로 갱신 가능 상태로 처리
      account.update_column(:connected, true) unless account.connected?

      svc = Gmail::GmailService.new(account)

      after_ts = since_date.to_time.to_i
      query    = "after:#{after_ts} category:primary"

      puts "[GmailBackfill]   Gmail 검색 중 (query: #{query}, max: 500)..."
      messages = svc.fetch_recent_messages(max: 500, query: query)
      puts "[GmailBackfill]   → #{messages.size}개 메시지 조회됨"

      messages.each_with_index do |msg, idx|
        parsed = svc.parse_message(msg)
        next unless parsed

        # 이미 임포트된 메일 스킵
        if Order.exists?(source_email_id: parsed[:id])
          total_skipped += 1
          print "s"
          next
        end

        detection = Gmail::RfqDetectorService.new(parsed).detect

        unless detection[:rfq_verdict] == :confirmed
          print "."
          next
        end

        order = Gmail::EmailToOrderService.new(account, parsed, detection).create_order!

        if order
          Gmail::EmailAttachmentExtractorService.new(svc, msg, order).extract_and_attach!
          total_new += 1
          print "+"
        else
          print "x"
        end

        # Gmail API quota 보호: 10건마다 0.5초 대기
        sleep(0.5) if (idx + 1) % 10 == 0
      rescue => e
        Rails.logger.error "[GmailBackfill] 메시지 처리 오류: #{e.message}"
        print "!"
      end

      puts ""
    end

    puts ""
    puts "[GmailBackfill] 완료 — 신규 Order: #{total_new}개, 스킵(기존): #{total_skipped}개"
    puts "[GmailBackfill] 범례: + 신규생성  . RFQ아님  s 기존존재  x 저장실패  ! 오류"
  end

  desc "Gmail 연결 상태 및 토큰 유효성 점검"
  task check_accounts: :environment do
    accounts = EmailAccount.all.includes(:user)

    if accounts.empty?
      puts "[GmailCheck] 등록된 Gmail 계정 없음"
      next
    end

    puts "[GmailCheck] Gmail 계정 점검 (#{accounts.size}개)"
    puts "-" * 60

    accounts.each do |acc|
      status = if !acc.connected?
        "미연결 (재인증 필요)"
      elsif acc.token_expired? && !acc.needs_refresh?
        "토큰 만료 + refresh_token 없음 (재인증 필요)"
      elsif acc.needs_refresh?
        "access_token 만료 (refresh_token으로 갱신 가능)"
      else
        "정상"
      end

      last_sync = acc.last_synced_at ? acc.last_synced_at.strftime("%Y-%m-%d %H:%M") : "동기화 없음"
      puts "  #{acc.email} [#{acc.user.name}]"
      puts "    상태: #{status}"
      puts "    마지막 동기화: #{last_sync}"

      order_count = Order.where(user: acc.user).count
      puts "    연동 Order: #{order_count}개"
      puts ""
    end
  end
end
