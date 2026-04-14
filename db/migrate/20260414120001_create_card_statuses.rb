class CreateCardStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :card_statuses do |t|
      t.string  :key,          null: false
      t.string  :name,         null: false
      t.string  :bg_color,     null: false, limit: 7
      t.string  :border_color, null: false, limit: 7
      t.string  :text_color,   null: false, limit: 7
      t.integer :position,     null: false, default: 0
      t.boolean :is_system,    null: false, default: false
      t.boolean :is_default,   null: false, default: false
      t.text    :auto_rule                                   # JSON string, SQLite에는 jsonb 없음
      t.integer :auto_priority, null: false, default: 0
      t.timestamps
    end

    add_index :card_statuses, :key,      unique: true
    add_index :card_statuses, :position
    # SQLite partial unique: is_default=1 인 레코드 최대 1건 보장
    add_index :card_statuses, :is_default,
              unique: true,
              where:  "is_default = 1",
              name:   "index_card_statuses_on_single_default"
  end
end
