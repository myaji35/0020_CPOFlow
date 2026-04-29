class AddKanbanPerfIndexesToOrders < ActiveRecord::Migration[8.1]
  # 칸반 첫 렌더 쿼리(2.7s → 0.5s 목표) 가속용 복합 인덱스.
  # 운영 분포: active 11,441 / root 4,761 / new_rfq 4,753 (rfq_triage 노출 171).
  # parent_order_id IS NULL + archived_at IS NULL 조합이 모든 컬럼 쿼리의 시작점.

  def change
    # 컬럼 쿼리: where(archived_at: nil, parent_order_id: nil, status: col)
    add_index :orders,
              [ :archived_at, :parent_order_id, :status ],
              name: "idx_orders_kanban_root_status",
              if_not_exists: true

    # new_rfq 컬럼 전용: + rfq_status (KANBAN_VISIBLE_RFQ_STATUSES 게이트)
    add_index :orders,
              [ :archived_at, :parent_order_id, :status, :rfq_status ],
              name: "idx_orders_kanban_inbox_gate",
              if_not_exists: true

    # board_scoped_orders 분기: kanban_board_id 별 + root + status
    add_index :orders,
              [ :kanban_board_id, :archived_at, :parent_order_id, :status ],
              name: "idx_orders_kanban_board_status",
              if_not_exists: true
  end
end
