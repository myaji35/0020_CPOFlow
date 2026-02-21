class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.references :country,             null: false, foreign_key: true
      t.string     :name,                null: false
      t.string     :name_en
      t.string     :company_type,        null: false, default: "branch"
      t.string     :registration_number
      t.string     :address
      t.boolean    :active,              null: false, default: true

      t.timestamps
    end
    add_index :companies, [ :country_id, :name ]
  end
end
