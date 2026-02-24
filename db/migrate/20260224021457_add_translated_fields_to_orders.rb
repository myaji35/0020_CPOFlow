class AddTranslatedFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :translated_subject, :text
    add_column :orders, :translated_body, :text
  end
end
