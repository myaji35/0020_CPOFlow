class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :title
      t.string :customer_name
      t.text :description
      t.integer :status, default: 0, null: false
      t.integer :priority, default: 1, null: false
      t.date :due_date
      t.string :source_email_id
      t.string :original_email_subject
      t.text :original_email_body
      t.string :original_email_from
      t.string :tags
      t.references :user, null: false, foreign_key: true
      t.string :item_name
      t.integer :quantity
      t.string :currency, default: "USD"
      t.decimal :estimated_value, precision: 12, scale: 2

      t.timestamps
    end

    add_index :orders, :status
    add_index :orders, :due_date
    add_index :orders, :source_email_id, unique: true, where: "source_email_id IS NOT NULL"
  end
end
