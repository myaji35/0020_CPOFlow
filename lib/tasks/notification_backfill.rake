# frozen_string_literal: true
# AUDIT-008: notification_type NULL 백필 태스크
# 실행: bin/rails notifications:backfill_nil_types

namespace :notifications do
  desc "notification_type이 nil인 알림을 title/body 키워드로 분류·백필"
  task backfill_nil_types: :environment do
    nil_records = Notification.where(notification_type: nil)
    total = nil_records.count

    if total.zero?
      puts "백필 대상 없음 (notification_type nil = 0건)"
      next
    end

    puts "백필 시작: #{total}건"

    counts = Hash.new(0)

    nil_records.find_each do |n|
      text = "#{n.title} #{n.body}".to_s.downcase

      inferred = if text.match?(/오버듀|overdue|긴급.*경과/)
                   "overdue_escalation"
                 elsif text.match?(/비자|visa/)
                   "visa"
                 elsif text.match?(/계약|contract/)
                   "contract"
                 elsif text.match?(/ecount|전표/)
                   "ecount_slip_failed"
                 elsif text.match?(/환영|oauth|가입/)
                   "oauth_signup"
                 else
                   "system"
                 end

      n.update_column(:notification_type, inferred)
      counts[inferred] += 1
    end

    puts "백필 완료:"
    counts.sort_by { |_, v| -v }.each { |type, cnt| puts "  #{type}: #{cnt}" }
    puts "남은 nil: #{Notification.where(notification_type: nil).count}건"
  end
end
