# frozen_string_literal: true

# 견적의뢰(RFQ)가 아닌 메일이 Inbox에 올라온 버그 정리
# - rfq_excluded Order: 광고/프로모션/알림 메일 → 삭제
# - rfq_uncertain Order 중 자사 도메인 발송분 → 삭제
class CleanupNonRfqInboxOrders < ActiveRecord::Migration[8.1]
  OWN_DOMAINS = %w[atoz2010.com koreabmt.com ddtl.co.kr].freeze

  def up
    # 1. rfq_excluded(2) 상태이면서 inbox(0)에 있는 Order 삭제
    excluded_ids = exec_query(<<~SQL).rows.flatten
      SELECT id FROM orders
      WHERE rfq_status = 2 AND status = 0
    SQL

    if excluded_ids.any?
      say "Deleting #{excluded_ids.size} rfq_excluded inbox orders: #{excluded_ids}"
      cleanup_orders(excluded_ids)
    end

    # 2. rfq_uncertain(1) + inbox(0) + 자사 도메인 발송 Order 삭제
    uncertain_orders = exec_query(<<~SQL).rows
      SELECT id, original_email_from FROM orders
      WHERE rfq_status = 1 AND status = 0
    SQL

    own_domain_ids = uncertain_orders.select do |_id, from_email|
      OWN_DOMAINS.any? { |d| from_email.to_s.include?("@#{d}") || from_email.to_s.include?("via ") }
    end.map(&:first)

    if own_domain_ids.any?
      say "Deleting #{own_domain_ids.size} uncertain inbox orders from own domains: #{own_domain_ids}"
      cleanup_orders(own_domain_ids)
    end
  end

  def down
    # 삭제된 Order는 복원 불가 — 재동기화로 복구 가능
    say "This migration is not reversible. Re-run EmailSyncJob to re-import if needed."
  end

  private

  def cleanup_orders(order_ids)
    return if order_ids.empty?
    id_list = order_ids.join(",")

    # 종속 레코드 먼저 삭제
    exec_delete("DELETE FROM activities WHERE order_id IN (#{id_list})")
    exec_delete("DELETE FROM assignments WHERE order_id IN (#{id_list})")
    exec_delete("DELETE FROM comments WHERE order_id IN (#{id_list})")
    exec_delete("DELETE FROM tasks WHERE order_id IN (#{id_list})")
    exec_delete("DELETE FROM rfq_feedbacks WHERE order_id IN (#{id_list})")
    exec_delete("DELETE FROM orders WHERE id IN (#{id_list})")
  end

  def exec_query(sql)
    ActiveRecord::Base.connection.exec_query(sql)
  end

  def exec_delete(sql)
    ActiveRecord::Base.connection.execute(sql)
  end
end
