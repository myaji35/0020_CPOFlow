# ISS-344: EmailAccount의 email 전역 unique → (email, user_id) composite unique
# 이유: 같은 Gmail을 여러 user가 각자 connect할 수 있어야 함 (callback 시 user_id 덮어쓰기 방지)
class ChangeEmailAccountsUniqueToComposite < ActiveRecord::Migration[8.1]
  def up
    remove_index :email_accounts, :email
    add_index :email_accounts, [ :email, :user_id ], unique: true, name: "index_email_accounts_on_email_and_user_id"
    add_index :email_accounts, :email, name: "index_email_accounts_on_email_lookup"
  end

  def down
    remove_index :email_accounts, name: "index_email_accounts_on_email_lookup"
    remove_index :email_accounts, name: "index_email_accounts_on_email_and_user_id"
    add_index :email_accounts, :email, unique: true
  end
end
