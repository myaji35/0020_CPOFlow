class AddFksToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :client,   foreign_key: true
    add_reference :orders, :supplier, foreign_key: true
    add_reference :orders, :project,  foreign_key: true
  end
end
