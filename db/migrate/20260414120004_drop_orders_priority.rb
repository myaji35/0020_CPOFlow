class DropOrdersPriority < ActiveRecord::Migration[8.1]
  def up
    remove_column :orders, :priority
  end

  def down
    add_column :orders, :priority, :integer, default: 1
  end
end
