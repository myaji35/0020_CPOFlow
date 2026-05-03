# AUDIT-003: due_date NULL Order의 단계별 기본 SLA 백필
# 대상: 최근 30일 내 생성된 due_date nil Order만 (보수적 범위)
# 실행:
#   bin/rails order:backfill_due_dates              (실제 적용)
#   DRY_RUN=1 bin/rails order:backfill_due_dates    (카운트만, DB 변경 없음)

namespace :order do
  desc "due_date nil Order(최근 30일)에 단계별 기본 SLA 날짜 백필"
  task backfill_due_dates: :environment do
    dry_run   = ENV["DRY_RUN"].to_s == "1"
    batch_size = 200
    cutoff     = 30.days.ago

    scope = Order.where(due_date: nil).where("created_at >= ?", cutoff)
    total = scope.count

    puts "[order:backfill_due_dates] 대상: #{total}건 (최근 30일, due_date nil)"
    puts "[order:backfill_due_dates] DRY_RUN 모드 — DB 변경 없음" if dry_run

    if total == 0
      puts "[order:backfill_due_dates] 처리할 대상 없음. 종료."
      next
    end

    updated = 0

    Order.transaction do
      scope.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |order|
          computed = order.default_due_date_for
          next if computed.nil?

          unless dry_run
            order.update_column(:due_date, computed.to_date)
          end
          updated += 1
        end
        print "."
      end
      raise ActiveRecord::Rollback if dry_run
    end

    puts ""
    if dry_run
      puts "[order:backfill_due_dates] DRY_RUN 결과: 업데이트 예상 #{updated}건 (실제 변경 없음)"
    else
      puts "[order:backfill_due_dates] 완료: #{updated}건 업데이트"
      remaining = Order.where(due_date: nil).count
      puts "[order:backfill_due_dates] 잔여 NULL: #{remaining}건"
    end
  end
end
