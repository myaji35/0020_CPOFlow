class CreateKanbanBoards < ActiveRecord::Migration[8.1]
  def change
    create_table :kanban_boards do |t|
      t.string :name, null: false
      t.string :board_type, default: "custom"
      t.string :description
      t.string :color_palette, default: "corporate"
      t.integer :position, default: 0
      t.boolean :is_default, default: false
      t.references :owner, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end
    add_reference :card_statuses, :kanban_board, foreign_key: true, null: true
    add_reference :orders, :kanban_board, foreign_key: true, null: true
    add_index :kanban_boards, :position
  end
end
