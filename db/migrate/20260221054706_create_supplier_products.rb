class CreateSupplierProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :supplier_products do |t|
      t.references :supplier,     null: false, foreign_key: true
      t.references :product,      null: false, foreign_key: true
      t.decimal :price,           precision: 10, scale: 2
      t.string  :currency,        default: "USD"
      t.integer :lead_time_days
      t.string  :notes

      t.timestamps
    end

    add_index :supplier_products, [ :supplier_id, :product_id ], unique: true
  end
end
