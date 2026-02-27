# frozen_string_literal: true

class AddEcountApiFields < ActiveRecord::Migration[8.1]
  def change
    # orders: 전표 번호 + 마지막 eCount 전송 시각
    add_column :orders, :ecount_slip_no,   :string
    add_column :orders, :ecount_synced_at, :datetime

    # products: 재고 수량 + 동기화 시각
    add_column :products, :stock_quantity,   :integer, default: 0
    add_column :products, :ecount_synced_at, :datetime

    # clients: 동기화 시각 (ecount_code 컬럼 이미 존재)
    add_column :clients, :ecount_synced_at, :datetime

    # suppliers: 동기화 시각 (ecount_code 컬럼 이미 존재)
    add_column :suppliers, :ecount_synced_at, :datetime

    add_index :orders, :ecount_slip_no
  end
end
