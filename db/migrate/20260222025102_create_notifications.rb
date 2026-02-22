class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.integer :user_id
      t.string :notifiable_type
      t.integer :notifiable_id
      t.string :title
      t.text :body
      t.string :notification_type
      t.datetime :read_at

      t.timestamps
    end
  end
end
