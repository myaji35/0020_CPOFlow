# frozen_string_literal: true

# Ariba 링크가 있는데 첨부 PDF가 저장되지 않은 Order 전수 재수집
#
# 사용:
#   bin/rails "ariba:backfill"                       # 전체, 기본 배치 50 / 분당 5
#   bin/rails "ariba:backfill[2025-10-01,50,5]"      # since, batch_size, per_minute
#   bin/rails "ariba:backfill_dry_run"               # 대상 건수만 확인
namespace :ariba do
  desc "Ariba 링크 보유 + 첨부 누락 Order 재수집 (since, batch_size, per_minute)"
  task :backfill, [ :since, :batch_size, :per_minute ] => :environment do |_, args|
    since_str   = args[:since].presence || "2025-10-01"
    batch_size  = (args[:batch_size].presence || 50).to_i
    per_minute  = (args[:per_minute].presence || 5).to_i
    since_time  = Time.zone.parse(since_str)

    scope = Order.where("orders.created_at >= ?", since_time)
                 .where("sap_portal_links LIKE ?", "%ariba.com%")
                 .left_joins(attachments_attachments: :blob)
                 .where(active_storage_blobs: { id: nil })
                 .distinct

    total = scope.count
    puts "[ariba:backfill] since=#{since_str} batch_size=#{batch_size} per_minute=#{per_minute} total=#{total}"
    return if total.zero?

    interval_sec = (60.0 / per_minute).round(2)
    enqueued = 0
    skipped  = 0

    scope.find_each(batch_size: batch_size) do |order|
      links = Sap::AribaScraperService.extract_ariba_links(order)
      if links.empty?
        skipped += 1
        next
      end

      AribaFetchJob.set(wait: (enqueued * interval_sec).seconds)
                   .perform_later(order_id: order.id, force: false)
      enqueued += 1

      if (enqueued % 100).zero?
        puts "[ariba:backfill] progress: enqueued=#{enqueued}/#{total} skipped=#{skipped}"
      end
    end

    eta_minutes = (enqueued.to_f / per_minute).ceil
    puts "[ariba:backfill] done: enqueued=#{enqueued} skipped=#{skipped} eta≈#{eta_minutes}분 (#{(eta_minutes / 60.0).round(1)}시간)"
  end

  desc "재수집 대상 건수만 확인 (dry-run)"
  task :backfill_dry_run, [ :since ] => :environment do |_, args|
    since_time = Time.zone.parse(args[:since].presence || "2025-10-01")
    scope = Order.where("orders.created_at >= ?", since_time)
                 .where("sap_portal_links LIKE ?", "%ariba.com%")
                 .left_joins(attachments_attachments: :blob)
                 .where(active_storage_blobs: { id: nil })
                 .distinct
    puts "[ariba:backfill_dry_run] since=#{since_time.to_date} candidates=#{scope.count}"
  end
end
