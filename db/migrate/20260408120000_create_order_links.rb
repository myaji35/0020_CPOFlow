class CreateOrderLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :order_links do |t|
      t.references :source, polymorphic: true, null: false
      t.references :target, polymorphic: true, null: false
      t.string  :relation, null: false
      t.text    :metadata
      t.string  :status, null: false, default: "confirmed"
      t.float   :confidence, null: false, default: 1.0
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_index :order_links, [ :source_type, :source_id ], name: "idx_order_links_source"
    add_index :order_links, [ :target_type, :target_id ], name: "idx_order_links_target"
    add_index :order_links, [ :relation, :status ], name: "idx_order_links_rel_status"
    add_index :order_links,
              [ :source_type, :source_id, :target_type, :target_id, :relation ],
              unique: true, name: "idx_order_links_unique"
  end
end
