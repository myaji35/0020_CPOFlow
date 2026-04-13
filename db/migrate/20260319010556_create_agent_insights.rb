# frozen_string_literal: true

class CreateAgentInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_insights do |t|
      t.references :order,    null: false, foreign_key: true
      t.references :supplier, foreign_key: true
      t.string     :insight_type, null: false
      t.integer    :severity, default: 0
      t.string     :title, null: false
      t.text       :body
      t.json       :metadata, default: {}
      t.boolean    :dismissed, default: false
      t.boolean    :useful
      t.datetime   :expires_at
      t.timestamps
    end

    add_index :agent_insights, [ :order_id, :insight_type ], name: "idx_insights_order_type"
    add_index :agent_insights, :expires_at
    add_index :agent_insights, [ :dismissed, :expires_at ], name: "idx_insights_active"
  end
end
