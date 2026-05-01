class AddContactPersonIdToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :contact_person, null: true, foreign_key: true, index: true
  end
end
