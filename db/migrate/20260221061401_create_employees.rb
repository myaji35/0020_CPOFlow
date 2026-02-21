class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.references :user,            foreign_key: true, null: true
      t.string  :name,               null: false
      t.string  :name_en
      t.string  :nationality,        null: false, default: "KR"
      t.string  :passport_number
      t.date    :date_of_birth
      t.string  :phone
      t.string  :emergency_contact
      t.string  :emergency_phone
      t.string  :department
      t.string  :job_title
      t.string  :employment_type,    null: false, default: "regular"
      t.date    :hire_date
      t.date    :termination_date
      t.boolean :active,             null: false, default: true
      t.text    :notes
      t.timestamps
    end

    add_index :employees, :name
    add_index :employees, :nationality
    add_index :employees, :active
  end
end
