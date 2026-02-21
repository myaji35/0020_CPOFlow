# frozen_string_literal: true

class CreateSheetsSyncLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :sheets_sync_logs do |t|
      t.string   :status,          null: false, default: "pending"
      t.string   :spreadsheet_id
      t.integer  :orders_count,    default: 0
      t.integer  :projects_count,  default: 0
      t.integer  :employees_count, default: 0
      t.integer  :visas_count,     default: 0
      t.text     :error_message
      t.datetime :synced_at
      t.timestamps
    end

    add_index :sheets_sync_logs, :status
    add_index :sheets_sync_logs, :created_at
  end
end
