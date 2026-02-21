class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string  :name,                null: false
      t.string  :code,                null: false
      t.string  :country,             null: false, default: "AE"
      t.string  :industry
      t.string  :address
      t.string  :website
      t.string  :credit_grade
      t.date    :contract_start_date
      t.string  :payment_terms
      t.string  :currency,            default: "USD"
      t.string  :ecount_code
      t.text    :notes
      t.boolean :active,              default: true, null: false

      t.timestamps
    end

    add_index :clients, :code,        unique: true
    add_index :clients, :ecount_code
    add_index :clients, :country
  end
end
