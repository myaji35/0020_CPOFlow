class AddPerfIndexes < ActiveRecord::Migration[8.1]
  # 운영 DB 진단(2026-05-11) 결과:
  # - orders.status / created_at 인덱스 없음 → 칸반 쿼리 풀스캔 (699ms)
  # - activities.created_at 인덱스 없음 → 활동 로그 풀스캔 (205ms)
  # - classification_logs.created_at 인덱스 없음 → 14K rows 풀스캔
  # 권장 효과: 23~40배 단축 (각 ~30ms / ~5ms)
  def change
    add_index :orders, [ :status, :created_at ], if_not_exists: true,
              name: "idx_orders_on_status_and_created_at"
    add_index :activities, :created_at, if_not_exists: true,
              name: "idx_activities_on_created_at"
    add_index :classification_logs, :created_at, if_not_exists: true,
              name: "idx_classification_logs_on_created_at"
  end
end
