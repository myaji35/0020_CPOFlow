class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.string :code
      t.string :name
      t.string :country
      t.string :contact_email
      t.string :contact_phone
      t.string :ecount_code
      t.boolean :active, default: true, null: false
      t.text :notes

      t.timestamps
    end

    add_index :suppliers, :code, unique: true
    add_index :suppliers, :ecount_code
  end
end
