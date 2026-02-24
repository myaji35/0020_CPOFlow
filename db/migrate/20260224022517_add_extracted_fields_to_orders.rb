class AddExtractedFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :extracted_quantities, :text
    add_column :orders, :extracted_project_name, :string
    add_column :orders, :delivery_location, :string
    add_column :orders, :sender_domain, :string
  end
end
