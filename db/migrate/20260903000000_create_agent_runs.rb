class CreateAgentRuns < ActiveRecord::Migration[8.1]
  # 에이전트 실행의 상태, 비용, 지연 시간을 한곳에 기록한다.
  # source 복합 unique 인덱스는 기존 분석 로그 백필의 멱등성을 보장한다.
  def change
    create_table :agent_runs do |t|
      t.references :order, null: true, foreign_key: false, index: false # 주문 생성 전 실행도 기록한다.
      t.string :agent_name, null: false
      t.string :kind, null: false, default: "service"
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :duration_ms
      t.string :model
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.decimal :cost_usd, precision: 10, scale: 6
      t.text :error_message
      t.text :meta
      t.string :source_type
      t.bigint :source_id
      t.integer :parent_run_id

      t.timestamps
    end

    add_index :agent_runs, :created_at
    add_index :agent_runs, [ :agent_name, :created_at ]
    add_index :agent_runs, [ :order_id, :started_at ]
    add_index :agent_runs, :status
    add_index :agent_runs, :parent_run_id
    add_index :agent_runs, [ :source_type, :source_id ], unique: true
  end
end
