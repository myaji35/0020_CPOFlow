# frozen_string_literal: true

# 같은 gmail_thread_id를 가진 중복 루트 주문을 정리합니다.
# 가장 오래된 주문을 메인(루트)으로 유지하고, 나머지를 서브 주문으로 변환합니다.
#
# 실행: bin/rails fix_duplicate_thread_orders
# 확인만: bin/rails fix_duplicate_thread_orders DRY_RUN=1
desc "Fix duplicate root orders with same gmail_thread_id"
task fix_duplicate_thread_orders: :environment do
  dry_run = ENV["DRY_RUN"].present?
  puts dry_run ? "=== DRY RUN ===" : "=== FIXING DUPLICATES ==="

  dupes = Order.where(parent_order_id: nil)
               .where.not(gmail_thread_id: nil)
               .group(:gmail_thread_id)
               .having("COUNT(*) > 1")
               .pluck(:gmail_thread_id)

  puts "Found #{dupes.count} threads with duplicate root orders"

  fixed = 0
  dupes.each do |thread_id|
    roots = Order.where(gmail_thread_id: thread_id, parent_order_id: nil)
                 .order(created_at: :asc)

    main = roots.first
    extras = roots.offset(1)

    puts "\nThread: #{thread_id}"
    puts "  Main:  ##{main.id} (#{main.status}) — #{main.title&.truncate(60)}"

    extras.each do |extra|
      puts "  Sub:   ##{extra.id} (#{extra.status}) — #{extra.title&.truncate(60)}"
      unless dry_run
        extra.update_columns(parent_order_id: main.id)
        Activity.create(order: main, action: "duplicate_merged", user: main.user,
                        metadata: { merged_order_id: extra.id }.to_json)
      end
      fixed += 1
    end
  end

  puts "\n#{dry_run ? "Would fix" : "Fixed"}: #{fixed} duplicate orders across #{dupes.count} threads"
end
