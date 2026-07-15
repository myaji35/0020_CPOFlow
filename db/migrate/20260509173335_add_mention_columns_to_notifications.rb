# frozen_string_literal: true

class AddMentionColumnsToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :acknowledged_at,     :datetime
    add_column :notifications, :viewed_at,           :datetime
    add_column :notifications, :viewed_duration_sec, :integer
    add_column :notifications, :intent_level,        :integer, default: 0, null: false
    add_column :notifications, :sla_due_at,          :datetime

    add_index :notifications, [ :notifiable_type, :notifiable_id, :notification_type ],
              name: "idx_notifications_polymorphic_type"
    add_index :notifications, :acknowledged_at
    add_index :notifications, :sla_due_at
  end
end
