# frozen_string_literal: true

# Orders의 gmail_thread_id를 Gmail API로 역조회하여 채우는 백필 태스크
# Usage: bin/rails backfill:gmail_thread_id
namespace :backfill do
  desc "Fill gmail_thread_id for Orders that have source_email_id but no gmail_thread_id"
  task gmail_thread_id: :environment do
    targets = Order.where(gmail_thread_id: nil)
                   .where.not(source_email_id: nil)
                   .order(:id)

    total   = targets.count
    updated = 0
    failed  = 0

    puts "[BackfillGmailThreadId] #{total}건 처리 시작..."

    # 계정별로 묶어서 처리 (API 재사용)
    targets.each do |order|
      account = EmailAccount.first  # MVP: 단일 계정 가정
      next unless account

      begin
        svc = Gmail::GmailService.new(account)
        msg = svc.fetch_message(order.source_email_id)
        if msg&.thread_id
          order.update_column(:gmail_thread_id, msg.thread_id)
          updated += 1
          print "."
        else
          failed += 1
          print "x"
        end
      rescue => e
        Rails.logger.warn "[BackfillGmailThreadId] Order##{order.id} failed: #{e.message}"
        failed += 1
        print "!"
      end

      sleep 0.05  # Gmail API quota 보호
    end

    puts "\n[BackfillGmailThreadId] 완료 — updated: #{updated}, failed: #{failed}"
  end
end
