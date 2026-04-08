# Procurement Ontology M3 — 백그라운드 백필
#
# 사용:
#   bin/rails order_links:backfill_async
#
# 동작:
#   모든 Order에 SuggestOrderLinksJob.perform_later 를 batch enqueue.
#   1000개 단위로 끊어서 메모리 폭주 방지.
namespace :order_links do
  desc "Enqueue SuggestOrderLinksJob for every Order in 1000-batch chunks"
  task backfill_async: :environment do
    total = Order.count
    batch_size = 1000
    enqueued = 0
    Order.find_each(batch_size: batch_size) do |o|
      SuggestOrderLinksJob.perform_later(o.id)
      enqueued += 1
      puts "  ... enqueued #{enqueued}/#{total}" if (enqueued % 1000).zero?
    end
    puts "[order_links:backfill_async] Enqueued #{enqueued}/#{total} jobs"
  end
end
