class AddEmailSignatureToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :email_signature_json, :text
  end
end
