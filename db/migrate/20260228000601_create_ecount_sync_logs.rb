# frozen_string_literal: true

class CreateEcountSyncLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ecount_sync_logs do |t|
      t.string   :sync_type,     null: false  # products / customers / slip
      t.integer  :status,        null: false, default: 0
      # enum: pending(0) / running(1) / completed(2) / failed(3)

      t.integer  :total_count,   default: 0
      t.integer  :success_count, default: 0
      t.integer  :error_count,   default: 0
      t.text     :error_details              # JSON: [{code:, error:}]

      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ecount_sync_logs, :sync_type
    add_index :ecount_sync_logs, :status
    add_index :ecount_sync_logs, :created_at
  end
end
