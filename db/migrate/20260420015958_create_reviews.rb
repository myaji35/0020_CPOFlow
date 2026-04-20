class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.integer :rating,     null: false
      t.text    :body,       null: false
      t.string  :email
      t.string  :email_hash
      t.integer :status,     null: false, default: 0
      t.string  :channel,    null: false, default: "in_app"
      t.string  :user_agent
      t.string  :ip_address

      t.timestamps
    end

    add_index :reviews, :status
    add_index :reviews, :created_at
  end
end
