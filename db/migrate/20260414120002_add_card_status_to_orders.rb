class AddCardStatusToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :card_status, foreign_key: true, null: true, index: true
    add_column    :orders, :card_status_manually_set_at, :datetime, null: true
    add_index     :orders, :card_status_manually_set_at
  end
end
