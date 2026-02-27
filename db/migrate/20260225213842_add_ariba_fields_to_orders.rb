class AddAribaFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :ariba_event_url, :string
    add_column :orders, :ariba_event_id, :string
    add_column :orders, :source_type, :integer, default: 0, null: false
    add_index  :orders, :ariba_event_id
  end
end
