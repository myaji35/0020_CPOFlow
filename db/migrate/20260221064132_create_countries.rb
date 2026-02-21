class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.string  :code,       null: false
      t.string  :name,       null: false
      t.string  :name_en,    null: false
      t.string  :region
      t.string  :flag_emoji
      t.integer :sort_order, default: 0

      t.timestamps
    end
    add_index :countries, :code, unique: true
  end
end
