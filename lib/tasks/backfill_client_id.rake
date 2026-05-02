# ISS-335: 기존 Order에 client_id 백필
# Usage: bin/rails rfp:backfill_client_id [DRY_RUN=true]
namespace :rfp do
  desc "ISS-335: 기존 Order에 client_id 자동 매핑 백필"
  task backfill_client_id: :environment do
    dry_run = ENV["DRY_RUN"] == "true"
    puts "[Rfp::ClientMatcher] DRY_RUN=#{dry_run}"

    targets = Order.where(client_id: nil).where.not(sender_domain: [ nil, "" ])
    total = targets.count
    puts "Target orders: #{total}"

    counters = Hash.new(0)
    domain_breakdown = Hash.new { |h, k| h[k] = { matched: 0, skipped: 0, no_match: 0 } }

    targets.find_each.with_index do |order, i|
      result = Rfp::ClientMatcher.call(order)
      domain = order.sender_domain.to_s.downcase

      case result[:source]
      when "skipped"
        counters[:skipped] += 1
        domain_breakdown[domain][:skipped] += 1
      when "no_match"
        counters[:no_match] += 1
        domain_breakdown[domain][:no_match] += 1
      else
        counters[:matched] += 1
        domain_breakdown[domain][:matched] += 1
        order.update_column(:client_id, result[:client].id) unless dry_run
      end

      print "\r  진행: #{i + 1}/#{total} (matched=#{counters[:matched]} skipped=#{counters[:skipped]} no_match=#{counters[:no_match]})" if (i % 100).zero?
    end

    puts "\n\n--- 결과 요약 ---"
    puts "Matched:  #{counters[:matched]}"
    puts "Skipped:  #{counters[:skipped]} (internal/ariba relay)"
    puts "No Match: #{counters[:no_match]}"

    puts "\n--- 미매칭 도메인 Top 20 (수동 매핑 후보) ---"
    domain_breakdown
      .select { |_d, b| b[:no_match] > 0 }
      .sort_by { |_d, b| -b[:no_match] }
      .first(20)
      .each { |d, b| puts "  #{b[:no_match].to_s.rjust(5)} #{d}" }

    puts "\n#{dry_run ? "DRY RUN 완료 (DB 변경 없음)" : "백필 완료"}"
  end
end
