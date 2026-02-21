class AddOmniauthAndCompanyNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :company_name, :string
  end
end
