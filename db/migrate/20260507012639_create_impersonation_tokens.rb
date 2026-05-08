class CreateImpersonationTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :impersonation_tokens do |t|
      t.string     :token,          null: false
      t.references :admin,          null: false, foreign_key: { to_table: :users }
      t.references :target_user,    null: false, foreign_key: { to_table: :users }
      t.datetime   :expires_at,     null: false
      t.datetime   :used_at

      t.timestamps
    end
    add_index :impersonation_tokens, :token, unique: true
  end
end
