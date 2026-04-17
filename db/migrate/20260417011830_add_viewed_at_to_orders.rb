class AddViewedAtToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :viewed_at, :datetime
    add_index :orders, :viewed_at
  end
end
