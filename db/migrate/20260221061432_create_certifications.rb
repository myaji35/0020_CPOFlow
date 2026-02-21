class CreateCertifications < ActiveRecord::Migration[8.1]
  def change
    create_table :certifications do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :name,         null: false
      t.string :issuing_body
      t.date   :issued_date
      t.date   :expiry_date
      t.text   :notes
      t.timestamps
    end

    add_index :certifications, :expiry_date
  end
end
