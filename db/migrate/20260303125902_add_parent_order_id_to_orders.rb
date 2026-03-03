class AddParentOrderIdToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :parent_order_id, :integer, null: true
    add_index  :orders, :parent_order_id
  end
end
