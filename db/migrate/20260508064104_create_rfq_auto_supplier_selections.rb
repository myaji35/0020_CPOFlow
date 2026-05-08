class CreateRfqAutoSupplierSelections < ActiveRecord::Migration[8.1]
  # LAB / RFQ Auto D-5 — 분석 결과의 여러 공급사 후보 중 사용자가 선택한 것 기록.
  # 같은 (analysis, item_idx, supplier_name) 조합 unique → 토글 동작.
  def change
    create_table :rfq_auto_supplier_selections do |t|
      t.integer :rfq_auto_analysis_id, null: false
      t.integer :supplier_id                          # local DB 매칭이면 set, web 결과면 null
      t.integer :item_idx,           null: false       # step2 items의 idx (1~N)
      t.string  :item_keyword                          # 표시용
      t.string  :supplier_name,      null: false
      t.string  :contact_email
      t.string  :contact_phone
      t.string  :website
      t.string  :country
      t.string  :source              # local_db / web_search / datago / google_cse / csv_upload
      t.integer :confidence
      t.string  :source_url
      t.integer :selected_by_user_id, null: false
      t.datetime :emailed_at                           # D-6 발송 기록
      t.timestamps
    end
    add_index :rfq_auto_supplier_selections, :rfq_auto_analysis_id, name: "idx_rfq_supplier_sel_analysis"
    add_index :rfq_auto_supplier_selections, [ :rfq_auto_analysis_id, :item_idx, :supplier_name ],
              unique: true, name: "idx_rfq_supplier_sel_unique"
  end
end
