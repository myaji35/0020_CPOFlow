# frozen_string_literal: true

class AddMentionSummaryToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :mention_total_count,        :integer, default: 0, null: false
    add_column :orders, :mention_unread_count,       :integer, default: 0, null: false
    add_column :orders, :mention_viewed_only_count,  :integer, default: 0, null: false
    add_column :orders, :mention_acknowledged_count, :integer, default: 0, null: false
    add_column :orders, :mention_sla_overdue_count,  :integer, default: 0, null: false
    add_column :orders, :mention_worst_state,        :string

    add_index :orders, :mention_total_count,
              name: "idx_orders_mention_total",
              where: "mention_total_count > 0"
  end
end
