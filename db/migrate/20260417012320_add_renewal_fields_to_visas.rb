class AddRenewalFieldsToVisas < ActiveRecord::Migration[8.1]
  def change
    add_column :visas, :renewal_started_at, :datetime
    add_column :visas, :renewal_status, :string
    add_column :visas, :renewal_note, :text
  end
end
