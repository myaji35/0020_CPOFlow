# ISS-332: 경고장(Warning) 모델 — 인사 처분 시스템
class CreateWarnings < ActiveRecord::Migration[8.1]
  def change
    create_table :warnings do |t|
      t.references :employee,   null: false, foreign_key: true
      t.references :issued_by,  null: true,  foreign_key: { to_table: :users }
      t.datetime   :issued_at,  null: false
      t.string     :category,   null: false, default: "other"      # tardiness/absence/quality/safety/behavior/other
      t.string     :severity,   null: false, default: "verbal"     # verbal/written/final/suspension/termination
      t.string     :subject,    null: false
      t.text       :description
      t.date       :effective_until
      t.datetime   :acknowledged_at
      t.text       :acknowledged_signature
      t.string     :status,     null: false, default: "active"      # active/acknowledged/expired/revoked
      t.timestamps
    end
    add_index :warnings, [ :employee_id, :issued_at ]
    add_index :warnings, :status
  end
end
