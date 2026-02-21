class CreateMenuPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :menu_permissions do |t|
      t.string  :role,        null: false
      t.string  :menu_key,    null: false
      t.boolean :can_read,    null: false, default: true
      t.boolean :can_create,  null: false, default: false
      t.boolean :can_update,  null: false, default: false
      t.boolean :can_delete,  null: false, default: false
      t.timestamps
    end

    add_index :menu_permissions, [:role, :menu_key], unique: true
  end
end
