class AddEncryptedTokensToEmailAccounts < ActiveRecord::Migration[8.1]
  def change
    # Rename old generic token column to explicit access token column
    rename_column :email_accounts, :gmail_token_ciphertext, :gmail_access_token_ciphertext
    # gmail_refresh_token_ciphertext already exists from initial migration
    # Add scope and metadata fields
    add_column :email_accounts, :oauth_scope, :string
    add_column :email_accounts, :connected, :boolean, default: false, null: false
  end
end
