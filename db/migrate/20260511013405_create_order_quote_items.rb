class CreateOrderQuoteItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_quote_items do |t|
      t.references :order, null: false, foreign_key: true, index: false
      t.references :source_attachment, foreign_key: { to_table: :active_storage_attachments }, index: false
      t.integer :row_no, null: false, default: 1
      t.string  :item
      t.text    :description
      t.string  :model_part_no
      t.string  :manufacturer_brand
      t.string  :unit
      t.decimal :qty, precision: 12, scale: 3
      t.text    :remarks
      t.boolean :user_edited, null: false, default: false
      t.references :edited_by_user, foreign_key: { to_table: :users }, index: false

      t.timestamps
    end

    add_index :order_quote_items, %i[order_id row_no]
    add_index :order_quote_items, :source_attachment_id, name: "idx_oqi_on_source_attachment"
  end
end
