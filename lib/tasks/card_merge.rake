namespace :orders do
  desc "동일 reference_no 중복 카드를 parent_order_id로 병합 (가장 오래된 카드를 메인으로)"
  task merge_duplicates: :environment do
    merged_count = 0
    group_count  = 0

    duplicate_refs = Order.where.not(reference_no: nil)
                          .where(parent_order_id: nil)
                          .group(:reference_no)
                          .having("COUNT(*) > 1")
                          .pluck(:reference_no)

    puts "중복 reference_no 그룹: #{duplicate_refs.size}개"

    duplicate_refs.each do |ref_no|
      orders = Order.where(reference_no: ref_no)
                    .where(parent_order_id: nil)
                    .order(created_at: :asc)
                    .to_a

      # 진행 중(inbox 이외) 카드가 있으면 그것을 메인으로, 없으면 가장 오래된 것
      main = orders.find { |o| o.status != "inbox" } || orders.first
      subs = orders.reject { |o| o.id == main.id }

      subs.each do |sub|
        sub.update!(parent_order_id: main.id)
        merged_count += 1
        puts "  [병합] Order##{sub.id} (#{sub.status}) → 메인 Order##{main.id} (ref: #{ref_no})"
      end

      group_count += 1
    end

    puts "\n완료: #{group_count}개 그룹, #{merged_count}건 병합"
  end
end
