class AddUniqueIndexToEmailAccounts < ActiveRecord::Migration[8.1]
  def change
    # 중복 레코드 제거: 같은 email 중 id가 가장 큰 것(최신)만 남기고 나머지 삭제
    execute <<~SQL
      DELETE FROM email_accounts
      WHERE id NOT IN (
        SELECT MAX(id) FROM email_accounts GROUP BY email
      )
    SQL

    add_index :email_accounts, :email, unique: true
  end
end
