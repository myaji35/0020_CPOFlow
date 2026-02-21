class CreateVisas < ActiveRecord::Migration[8.1]
  def change
    create_table :visas do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :visa_type,       null: false
      t.string :issuing_country, null: false
      t.string :visa_number
      t.date   :issue_date
      t.date   :expiry_date,     null: false
      t.string :status,          null: false, default: "active"
      t.text   :notes
      t.timestamps
    end

    add_index :visas, [:employee_id, :status]
    add_index :visas, :expiry_date
  end
end
