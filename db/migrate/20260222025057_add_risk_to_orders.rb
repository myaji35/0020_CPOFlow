class AddRiskToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :risk_score, :integer
    add_column :orders, :risk_level, :string
    add_column :orders, :risk_updated_at, :datetime
  end
end
