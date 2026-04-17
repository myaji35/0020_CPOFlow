class AddFieldChangesToActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :field, :string
    add_column :activities, :old_value, :text
    add_column :activities, :new_value, :text
  end
end
