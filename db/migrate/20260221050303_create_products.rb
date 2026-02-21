class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :code
      t.string :name
      t.text :description
      t.string :unit
      t.string :category
      t.string :brand
      t.string :supplier_code
      t.decimal :unit_price, precision: 12, scale: 4
      t.string :currency, default: "USD"
      t.boolean :sika_product, default: false, null: false
      t.string :ecount_code
      t.boolean :active, default: true, null: false
      t.string :site_category  # nuclear/hydro/tunnel/gtx/general

      t.timestamps
    end

    add_index :products, :code, unique: true
    add_index :products, :ecount_code
    add_index :products, :sika_product
    add_index :products, :category
  end
end
