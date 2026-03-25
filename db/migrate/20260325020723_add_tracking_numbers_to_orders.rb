class AddTrackingNumbersToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :rfq_no, :string
    add_column :orders, :quo_no, :string
    add_column :orders, :po_no, :string
  end
end
