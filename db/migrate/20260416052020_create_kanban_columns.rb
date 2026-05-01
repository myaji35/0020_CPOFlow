class CreateKanbanColumns < ActiveRecord::Migration[8.1]
  def change
    create_table :kanban_columns do |t|
      t.references :kanban_board, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.integer :position, default: 0
      t.string :color, default: "#E5E7EB"
      t.boolean :is_final, default: false
      t.integer :wip_limit
      t.timestamps
    end
    add_index :kanban_columns, [ :kanban_board_id, :key ], unique: true
    add_index :kanban_columns, [ :kanban_board_id, :position ]
  end
end
