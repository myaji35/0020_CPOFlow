class AddRfpAnalysisFields < ActiveRecord::Migration[8.1]
  def change
    # orders: RFP 자동 분석 상태 추적 (ISS-293)
    add_column :orders, :rfp_analysis_state, :string, default: "pending"
    add_column :orders, :rfp_analyzed_at, :datetime

    # tasks: 자동 생성 태스크 메타데이터 (ISS-293)
    add_column :tasks, :source_attachment_id, :bigint
    add_column :tasks, :source_excerpt, :text
    add_column :tasks, :feedback_score, :integer
    add_column :tasks, :auto_generated, :boolean, default: false

    add_index :tasks, :source_attachment_id
    add_index :orders, :rfp_analysis_state
  end
end
