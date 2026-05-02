class CreateLeaves < ActiveRecord::Migration[8.1]
  def change
    create_table :leaves do |t|
      t.references :employee, null: false, foreign_key: true
      t.string  :leave_type,    null: false
      t.date    :start_date,    null: false
      t.date    :end_date,      null: false
      t.decimal :days_requested, precision: 4, scale: 1, null: false, default: 1.0
      t.text    :reason
      t.string  :status, null: false, default: "requested"
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      # 2단계 승인
      t.bigint  :manager_approved_by_id
      t.datetime :manager_approved_at
      t.bigint  :admin_approved_by_id
      t.datetime :admin_approved_at

      # 반려
      t.bigint  :rejected_by_id
      t.datetime :rejected_at
      t.text    :rejection_reason

      t.timestamps
    end

    add_index :leaves, :status
    add_index :leaves, :start_date
    add_index :leaves, [ :employee_id, :start_date ]

    add_foreign_key :leaves, :users, column: :manager_approved_by_id
    add_foreign_key :leaves, :users, column: :admin_approved_by_id
    add_foreign_key :leaves, :users, column: :rejected_by_id
  end
end
