class AddRfqStatusToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :rfq_status, :integer, default: 0
    # enum: { confirmed: 0, uncertain: 1, excluded: 2 }

    add_column :orders, :reply_draft, :text
    # 자동 생성된 답변 초안
  end
end
