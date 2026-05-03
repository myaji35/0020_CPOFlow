# frozen_string_literal: true

# AUDIT-002: 미배정 Order 일괄 자동 배정
#
# 사용법:
#   bin/rails order:bulk_auto_assign            # 실제 실행
#   DRY_RUN=1 bin/rails order:bulk_auto_assign  # 미리보기 (변경 없음)
#
def order_assigner_resolve_source(order)
  return "client"   if order.client&.default_assignee_id.present?
  return "supplier" if order.supplier&.default_assignee_id.present?
  branch = order.user&.branch
  return "branch"   if branch.present? && User.where(role: :admin, branch: branch).exists?
  "none"
end

namespace :order do
  desc "미배정 Order에 AutoAssignerService 일괄 실행 (DRY_RUN=1 로 미리보기)"
  task bulk_auto_assign: :environment do
    dry_run = ENV["DRY_RUN"].present?
    puts dry_run ? "=== DRY_RUN 모드 (변경 없음) ===" : "=== 실행 모드 ==="

    unassigned = Order.left_joins(:assignments).where(assignments: { id: nil }).distinct
    total = unassigned.count
    puts "미배정 Order: #{total}건"

    results = Hash.new(0)   # { "client" => N, "supplier" => N, "branch" => N, "none" => N }
    by_user_branch = Hash.new(0)
    assigned_count = 0

    unassigned.find_each do |order|
      source = order_assigner_resolve_source(order)
      results[source] += 1
      by_user_branch[order.user&.branch.to_s] += 1 if source != "none"

      unless dry_run
        user_id = AutoAssignerService.new(order).call
        assigned_count += 1 if user_id
      end
    end

    puts "\n--- 매핑 가능 건수 ---"
    puts "  client.default_assignee 기반: #{results['client']}건"
    puts "  supplier.default_assignee 기반: #{results['supplier']}건"
    puts "  branch admin 기반: #{results['branch']}건"
    puts "  매핑 불가: #{results['none']}건"
    puts "\n--- creator branch별 배정 가능 ---"
    by_user_branch.each { |branch, count| puts "  #{branch}: #{count}건" }

    if dry_run
      mappable = total - results["none"]
      puts "\nDRY_RUN 결과: 총 #{total}건 중 #{mappable}건 자동 배정 가능"
    else
      puts "\n완료: #{assigned_count}건 배정됨"
    end
  end
end
