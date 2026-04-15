class AddInboxPerfIndexesToOrders < ActiveRecord::Migration[8.1]
  # Inbox 1페이지 TTFB 1.6s → 300ms 목표.
  # 병목 쿼리:
  #   1) WHERE rfq_status = 'rfq_triage' → 풀스캔 13,158건
  #   2) WHERE status = 'new_rfq' AND rfq_status = 'rfq_pending' ORDER BY email_received_at DESC
  #   3) WHERE status != 'new_rfq' ORDER BY email_received_at DESC
  def up
    # 1) rfq_status 단독
    add_index :orders, :rfq_status, if_not_exists: true

    # 2) status + rfq_status 복합 — 사이드바 badge counts(CASE WHEN)에 유리
    add_index :orders, [ :status, :rfq_status ], if_not_exists: true, name: "index_orders_on_status_rfq_status"

    # 3) email_received_at DESC 정렬 + 필터링 결합 — not_archived + status
    # SQLite는 nulls last 지원 제한적 → COALESCE 인덱스는 별도 이슈, 기본 정렬 속도 개선
    add_index :orders, [ :archived_at, :email_received_at ], if_not_exists: true, name: "index_orders_on_archived_received"
  end

  def down
    remove_index :orders, name: "index_orders_on_archived_received", if_exists: true
    remove_index :orders, name: "index_orders_on_status_rfq_status", if_exists: true
    remove_index :orders, :rfq_status, if_exists: true
  end
end
