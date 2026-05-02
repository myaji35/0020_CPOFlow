# ISS-330: Order에 체크리스트 분석 결과 저장
# rfp_checklist_json 예시: {"AQ_GRADE":"A","DRAWING_NO":"DWG-2026-001","URGENCY":"D-3","CERT_REQ":["CE","UL"]}
class AddChecklistSummaryToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :rfp_checklist_json, :text
  end
end
