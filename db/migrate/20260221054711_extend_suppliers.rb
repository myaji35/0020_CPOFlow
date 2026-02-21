class ExtendSuppliers < ActiveRecord::Migration[8.1]
  def change
    add_column :suppliers, :address,        :string
    add_column :suppliers, :website,        :string
    add_column :suppliers, :credit_grade,   :string
    add_column :suppliers, :payment_terms,  :string
    add_column :suppliers, :lead_time_days, :integer
    add_column :suppliers, :currency,       :string, default: "USD"
    add_column :suppliers, :industry,       :string
  end
end
