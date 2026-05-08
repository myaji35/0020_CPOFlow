class CreateRfqAutoAnalyses < ActiveRecord::Migration[8.1]
  # LAB / RFQ Auto — Order 첨부 자동 분석 결과 영구 저장.
  # 단계별 결과/비용/시간을 JSON에 저장 → 재현성 + ROI 메트릭 누적.
  def change
    create_table :rfq_auto_analyses do |t|
      t.integer  :order_id, null: false
      t.integer  :user_id,  null: false  # 실행한 admin
      t.string   :status,   null: false, default: "pending"  # pending/running/completed/failed
      t.text     :steps                                      # JSON: { step1: {...}, step2: {...}, ... }
      t.text     :summary                                    # JSON: 최종 요약 (품목 N개, 공급사 N개 등)
      t.decimal  :cost_usd,    precision: 10, scale: 4, default: 0.0
      t.integer  :latency_ms,  default: 0
      t.string   :llm_model
      t.string   :feedback                                   # correct / wrong / partial / nil
      t.text     :error_message                              # 실패 시
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :rfq_auto_analyses, :order_id
    add_index :rfq_auto_analyses, :status
    add_index :rfq_auto_analyses, [ :user_id, :created_at ]
  end
end
