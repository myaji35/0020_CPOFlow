class AddRfpSummaryToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :rfp_summary_ko, :text
    add_column :orders, :rfp_summary_en, :text
    add_column :orders, :rfp_summary_generated_at, :datetime
  end
end
