class AddKanbanColumnIdToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :kanban_column, null: true, foreign_key: true
  end
end
