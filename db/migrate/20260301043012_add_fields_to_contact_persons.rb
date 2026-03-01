class AddFieldsToContactPersons < ActiveRecord::Migration[8.1]
  def change
    add_column :contact_persons, :mobile,            :string
    add_column :contact_persons, :department,        :string
    add_column :contact_persons, :linkedin,          :string
    add_column :contact_persons, :last_contacted_at, :datetime
    add_column :contact_persons, :source,            :string, default: "manual"

    add_index :contact_persons, :department
    add_index :contact_persons, :last_contacted_at
  end
end
