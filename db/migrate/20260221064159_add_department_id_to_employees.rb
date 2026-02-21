class AddDepartmentIdToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_reference :employees, :department, null: true, foreign_key: true
  end
end
