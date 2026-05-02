# ISS-330: 표준 체크리스트 시스템
# RFP 분석 시 LLM 프롬프트에 포함되어 자동 검증되는 항목들 (AQ 등급/도면번호/긴급도/인증 등)
class CreateChecklistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_items do |t|
      t.string  :code,        null: false              # 고유 코드 (예: AQ_GRADE)
      t.string  :name,        null: false              # 표시 이름 (예: AQ 등급)
      t.string  :name_en                                # 영문명 (UAE 직원용)
      t.string  :category,    null: false, default: "general"  # general/quality/cert/drawing/urgency
      t.text    :prompt_hint, null: false              # LLM 프롬프트에 들어갈 힌트
      t.text    :allowed_values                         # JSON 배열 (예: ["A","B","C","Reject"]) or null
      t.boolean :required,    null: false, default: false
      t.boolean :active,      null: false, default: true
      t.integer :position,    null: false, default: 0
      t.timestamps
    end
    add_index :checklist_items, :code, unique: true
    add_index :checklist_items, [ :category, :active ]
  end
end
