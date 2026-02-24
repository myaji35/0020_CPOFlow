class CreateRfqFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :rfq_feedbacks do |t|
      t.references :order,  null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true
      t.string  :verdict,        null: false   # "confirmed" | "rejected"
      t.string  :sender_domain                 # 학습용 발신 도메인
      t.string  :subject_pattern               # 학습용 제목 패턴 (첫 20자)
      t.text    :note                          # 사용자 메모 (선택)
      t.timestamps
    end

    add_index :rfq_feedbacks, [ :order_id, :user_id ], unique: true
    add_index :rfq_feedbacks, :sender_domain
    add_index :rfq_feedbacks, :verdict
  end
end
