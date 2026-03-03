class AddGmailThreadIdToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :gmail_thread_id, :string
    add_index :orders, :gmail_thread_id
  end
end
