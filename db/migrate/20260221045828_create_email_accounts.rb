class CreateEmailAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :email_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email
      t.text :gmail_token_ciphertext
      t.text :gmail_refresh_token_ciphertext
      t.datetime :last_synced_at
      t.datetime :token_expires_at

      t.timestamps
    end
  end
end
