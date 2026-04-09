class CreateClassificationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :classification_logs do |t|
      t.references :order, foreign_key: true, null: true   # null 허용: Order 생성 전 분류 로그 가능
      t.string  :email_message_id, index: true             # Gmail message id
      t.string  :classifier_version, null: false
      t.integer :stage_reached
      t.string  :verdict                                   # "confirmed" | "excluded" | "uncertain"
      t.boolean :is_rfq
      t.decimal :confidence, precision: 5, scale: 4
      t.boolean :would_exclude, default: false, null: false # Shadow Mode: v2가 excluded 판정했지만 실제 저장은 pending인 경우
      t.text    :reason
      t.decimal :cost_usd, precision: 10, scale: 6, default: 0
      t.integer :latency_ms
      t.boolean :cache_hit, default: false, null: false
      t.string  :model                                     # "rule-only" | "haiku-4.5" | "sonnet-4.5"

      t.timestamps
    end

    add_index :classification_logs, [:classifier_version, :created_at]
    add_index :classification_logs, :would_exclude
  end
end
