class AddEmployeeIdToAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :assignments, :employee_id, :integer
    add_index  :assignments, :employee_id
    add_index  :assignments, %i[order_id employee_id], unique: true, name: "index_assignments_on_order_id_and_employee_id"

    # user_id를 nullable로 변경 (기존 데이터 보존, 점진적 전환)
    change_column_null :assignments, :user_id, true

    # 기존 user_id 기반 배정 → Employee 연결 (user와 연결된 employee가 있으면 자동 매핑)
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE assignments
          SET employee_id = (
            SELECT id FROM employees WHERE user_id = assignments.user_id LIMIT 1
          )
          WHERE user_id IS NOT NULL
        SQL
      end
    end
  end
end
