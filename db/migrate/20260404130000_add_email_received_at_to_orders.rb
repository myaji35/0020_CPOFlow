# frozen_string_literal: true

class AddEmailReceivedAtToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :email_received_at, :datetime, default: nil
    add_index :orders, :email_received_at
  end
end
