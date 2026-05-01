class CreateTrackingCodesAndNumbers < ActiveRecord::Migration[8.1]
  def change
    create_table :tracking_codes do |t|
      t.string  :code,        null: false, limit: 3        # 예: RFQ, QUO, PO, INV
      t.string  :short_label, null: false, limit: 2        # 카드 표시용: R, Q, P, I
      t.string  :name                                       # 풀 라벨 (드로어용, 옵션)
      t.string  :color,        null: false, default: "#6366F1"
      t.integer :position,     null: false, default: 0
      t.boolean :active,       null: false, default: true
      t.timestamps
    end
    add_index :tracking_codes, :code, unique: true
    add_index :tracking_codes, :position

    create_table :tracking_numbers do |t|
      t.references :order,         null: false, foreign_key: true, index: true
      t.references :tracking_code, null: false, foreign_key: true, index: true
      t.string :value, null: false
      t.timestamps
    end
    add_index :tracking_numbers, [ :order_id, :tracking_code_id ], unique: true, name: "idx_tracking_numbers_order_code"
  end
end
