class CreateEmployeeAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :employee_assignments do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :project,  null: false, foreign_key: true
      t.string :role
      t.date   :start_date,   null: false
      t.date   :end_date
      t.string :status,       null: false, default: "active"
      t.text   :notes
      t.timestamps
    end

    add_index :employee_assignments, [:employee_id, :project_id]
    add_index :employee_assignments, [:project_id, :status]
  end
end
