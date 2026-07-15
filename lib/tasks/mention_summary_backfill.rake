# frozen_string_literal: true

# ISS-353 Phase 1 백필 — notifications.viewed_at = read_at 복사 + Order 카운터 캐시 재계산
#
# 사용:
#   bin/rails mentions:backfill_phase1            # 실제 실행
#   bin/rails mentions:backfill_phase1[true]      # dry-run (집계만)
#
# 동작:
#   1) 기존 멘션 알림 중 read_at 있는데 viewed_at 비어있는 건 → viewed_at = read_at 복사
#      (update_columns 사용 — after_commit 무발화로 broadcast 폭주 방지)
#   2) 영향받은 Order 별로 recompute_mention_summary! 호출 (find_each 100 batch)
#   3) 멱등성: 재실행 시 1단계 0건 보고

namespace :mentions do
  desc "Phase 1 백필: notifications.viewed_at = read_at 복사 + 영향 Order recompute"
  task :backfill_phase1, [ :dry_run ] => :environment do |_, args|
    dry = args[:dry_run] == "true"

    puts "[mention:backfill] dry_run=#{dry} 시작"

    target = Notification.where(notification_type: "mentioned")
                         .where.not(read_at: nil)
                         .where(viewed_at: nil)
    count = target.count
    puts "[1/2] viewed_at 백필 대상: #{count}건"

    unless dry
      target.find_each(batch_size: 1000).with_index do |n, i|
        n.update_columns(viewed_at: n.read_at)
        puts "  진행: #{i + 1}/#{count}" if ((i + 1) % 1000).zero?
      end
    end

    affected_order_ids = Notification.where(notification_type: "mentioned")
                                     .where(notifiable_type: "Order")
                                     .distinct
                                     .pluck(:notifiable_id)
    puts "[2/2] 영향 Order 재계산 대상: #{affected_order_ids.size}건"

    unless dry
      Order.where(id: affected_order_ids).find_each(batch_size: 100).with_index do |o, i|
        o.recompute_mention_summary!
        puts "  진행: #{i + 1}/#{affected_order_ids.size}" if ((i + 1) % 100).zero?
      end
    end

    puts "[mention:backfill] 완료 dry_run=#{dry}"
  end
end
