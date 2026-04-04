# frozen_string_literal: true

# 기존 Order의 email_received_at을 Gmail API에서 가져온 internalDate로 업데이트
# Usage: bin/rails email:backfill_dates
namespace :email do
  desc "Backfill email_received_at from Gmail API internalDate (metadata only, fast)"
  task backfill_dates: :environment do
    account = EmailAccount.where(connected: true).first
    unless account
      puts "No connected email account found"
      next
    end

    svc = Gmail::GmailService.new(account)
    orders = Order.where(email_received_at: nil).where.not(source_email_id: [nil, ""])
    total = orders.count
    puts "Backfilling #{total} orders..."

    updated = 0
    errors = 0
    orders.find_each(batch_size: 100).with_index do |order, idx|
      begin
        # metadata format — 헤더/본문 없이 internalDate만 가져옴 (빠름)
        msg = account.gmail_service_instance.get_user_message("me", order.source_email_id, format: "metadata", metadata_headers: ["Date"])
        if msg&.internal_date
          received_at = Time.at(msg.internal_date.to_i / 1000).utc
          order.update_column(:email_received_at, received_at)
          updated += 1
        end
      rescue => e
        errors += 1
      end

      if (idx + 1) % 200 == 0
        puts "  Progress: #{idx + 1}/#{total} (updated=#{updated}, errors=#{errors})"
      end
    end

    puts "Done: #{updated} updated, #{errors} errors out of #{total}"
  end
end
