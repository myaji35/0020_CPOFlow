class CreateAgentTrustLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_trust_levels do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :insight_type, null: false
      t.integer    :useful_count, default: 0
      t.integer    :dismiss_count, default: 0
      t.boolean    :auto_mode, default: false
      t.datetime   :auto_activated_at
      t.timestamps
    end
    add_index :agent_trust_levels, [:user_id, :insight_type], unique: true, name: "idx_trust_user_type"
  end
end
