class CreateEmploymentContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :employment_contracts do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :project,  foreign_key: true, null: true
      t.date    :start_date,    null: false
      t.date    :end_date
      t.decimal :base_salary,   precision: 12, scale: 2
      t.string  :currency,      null: false, default: "USD"
      t.string  :pay_frequency, null: false, default: "monthly"
      t.string  :status,        null: false, default: "active"
      t.text    :notes
      t.timestamps
    end

    add_index :employment_contracts, [:employee_id, :status]
    add_index :employment_contracts, :end_date
  end
end
