class CreateOrderQuotes < ActiveRecord::Migration[8.1]
  def change
    create_table :order_quotes do |t|
      t.integer :order_id
      t.integer :supplier_id
      t.decimal :unit_price
      t.string :currency
      t.integer :lead_time_days
      t.date :validity_date
      t.text :notes
      t.boolean :selected
      t.datetime :submitted_at

      t.timestamps
    end
  end
end
