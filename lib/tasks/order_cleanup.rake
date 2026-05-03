namespace :order do
  # AUDIT-001: new_rfq 컬럼 누적 정리
  # 30일 이상 업데이트 없는 new_rfq 건을 give_up으로 일괄 전환
  # 사용: bin/rails order:cleanup_stale_rfq
  desc "30일 이상 업데이트 없는 new_rfq 건을 give_up으로 일괄 전환"
  task cleanup_stale_rfq: :environment do
    stale_scope = Order.stale_new_rfq
    total = stale_scope.count
    puts "정리 대상: #{total}건 (30일 이상 미갱신 new_rfq)"

    if total.zero?
      puts "정리 대상 없음."
      next
    end

    moved = 0
    Order.transaction do
      stale_scope.in_batches(of: 1000) do |batch|
        count = batch.update_all(status: Order.statuses[:give_up], updated_at: Time.current)
        moved += count
        puts "  → #{moved}/#{total}건 처리 완료"
      end
    end

    puts "Moved #{moved} stale RFQs to give_up"
  end
end
