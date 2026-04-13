class AddClassifierFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :classifier_version, :string, default: "v1", null: false
    add_column :orders, :stage_reached, :integer
    add_column :orders, :stage1_latency_ms, :integer
    add_column :orders, :stage2_latency_ms, :integer
    add_column :orders, :stage3_latency_ms, :integer
    add_column :orders, :classification_confidence, :decimal, precision: 5, scale: 4
    add_column :orders, :cache_hit, :boolean, default: false, null: false

    add_index :orders, :classifier_version
    add_index :orders, [ :classifier_version, :created_at ]
  end
end
