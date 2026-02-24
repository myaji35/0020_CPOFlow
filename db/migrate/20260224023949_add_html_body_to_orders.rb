class AddHtmlBodyToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :original_email_html_body, :text
  end
end
