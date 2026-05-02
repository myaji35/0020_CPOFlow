class AddLeaveBalanceToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :employees, :annual_leave_balance, :decimal, precision: 5, scale: 1, default: 0.0, null: false
  end
end
