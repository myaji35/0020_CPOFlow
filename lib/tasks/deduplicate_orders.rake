# frozen_string_literal: true

# 같은 reference_no + original_email_subject를 가진 중복 Order를 정리합니다.
# (2개 Gmail 계정에서 같은 이메일을 동시 수신 → 같은 order가 2건씩 생성됨)
#
# 보존 기준: 첨부파일(attachments) 가장 많은 1건 (동일 시 id가 낮은 것)
# 나머지: archived_at = Time.current (soft delete)
#
# 실행:
#   bin/rails orders:deduplicate            # 실제 아카이브
#   bin/rails orders:deduplicate DRY_RUN=1  # 확인만 (변경 없음)

namespace :orders do
  desc "Deduplicate orders with same reference_no + original_email_subject (soft-archive duplicates)"
  task deduplicate: :environment do
    dry_run = ENV["DRY_RUN"].present?
    puts dry_run ? "=== DRY RUN (변경 없음) ===" : "=== 중복 Order 아카이브 실행 ==="
    puts ""

    # 1) 중복 그룹 찾기: reference_no + original_email_subject 기준
    groups = Order
      .where(archived_at: nil)                         # 이미 아카이브된 건 제외
      .where.not(reference_no: [ nil, "" ])
      .where.not(original_email_subject: [ nil, "" ])
      .group(:reference_no, :original_email_subject)
      .having("COUNT(*) > 1")
      .pluck(:reference_no, :original_email_subject)

    total_groups   = groups.size
    total_archived = 0
    total_kept     = 0

    puts "중복 그룹 수: #{total_groups}"
    puts "-" * 70

    groups.each_with_index do |(ref_no, subject), idx|
      orders = Order
        .where(archived_at: nil, reference_no: ref_no, original_email_subject: subject)
        .includes(attachments_attachments: :blob)
        .order(:id)
        .to_a

      next if orders.size < 2

      # 보존 기준: 첨부 가장 많은 것 → 동일 시 id 낮은 것
      keeper = orders.max_by { |o| [ o.attachments.size, -o.id ] }
      duplicates = orders - [ keeper ]

      if (idx < 20) || ((idx + 1) % 100 == 0) || (idx == total_groups - 1)
        puts "[#{idx + 1}/#{total_groups}] ref=#{ref_no}"
        puts "  subject: #{subject.truncate(80)}"
        puts "  보존: ##{keeper.id} (첨부 #{keeper.attachments.size}건)"
        duplicates.each do |dup|
          puts "  아카이브: ##{dup.id} (첨부 #{dup.attachments.size}건)"
        end
      end

      unless dry_run
        dup_ids = duplicates.map(&:id)
        Order.where(id: dup_ids).update_all(archived_at: Time.current)

        # Activity 기록 (action 필드에 요약)
        duplicates.each do |dup|
          Activity.create(
            order: keeper,
            action: "duplicate_archived(##{dup.id})",
            user_id: keeper.user_id
          )
        rescue => e
          # Activity 기록 실패해도 아카이브 자체는 이미 완료
          Rails.logger.warn "[dedup] Activity 기록 실패: #{e.message}"
        end
      end

      total_archived += duplicates.size
      total_kept += 1
    end

    puts ""
    puts "=" * 70
    puts "결과 요약:"
    puts "  중복 그룹: #{total_groups}개"
    puts "  보존: #{total_kept}건"
    puts "  #{dry_run ? '아카이브 예정' : '아카이브 완료'}: #{total_archived}건"
    puts "=" * 70

    if dry_run
      puts ""
      puts "실제 실행: bin/rails orders:deduplicate"
    end
  end
end
