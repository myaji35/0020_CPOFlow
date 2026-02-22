class AddLlmAnalysisToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :rfq_confidence,    :string,  default: "none"  # none|low|medium|high
    add_column :orders, :rfq_score,         :integer, default: 0       # 0-100
    add_column :orders, :llm_analysis,      :text                       # JSON: LLM 분석 결과
    add_column :orders, :attachment_urls,   :text                       # JSON array: 첨부파일 URLs
    add_column :orders, :extracted_links,   :text                       # JSON array: 이메일 내 링크들
    add_column :orders, :llm_analyzed_at,   :datetime
  end
end
