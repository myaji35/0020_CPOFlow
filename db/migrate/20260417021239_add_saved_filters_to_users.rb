class AddSavedFiltersToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :saved_filters, :json
  end
end
