class AddReferenceNoToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :reference_no, :string
    add_index  :orders, :reference_no
  end
end
