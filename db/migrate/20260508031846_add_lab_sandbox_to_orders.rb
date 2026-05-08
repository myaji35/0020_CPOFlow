class AddLabSandboxToOrders < ActiveRecord::Migration[8.1]
  # LAB / RFQ Auto — 샌드박스 Order 플래그.
  # true이면 칸반/inbox/리포트 모두에서 제외, LAB에서만 보임.
  # 운영 데이터 오염 없이 임의 첨부파일로 분석 테스트 가능.
  def change
    add_column :orders, :lab_sandbox, :boolean, default: false, null: false
    add_index  :orders, :lab_sandbox
  end
end
