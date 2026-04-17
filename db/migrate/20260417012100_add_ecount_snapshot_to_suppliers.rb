class AddEcountSnapshotToSuppliers < ActiveRecord::Migration[8.1]
  def change
    add_column :suppliers, :ecount_snapshot, :json
  end
end
