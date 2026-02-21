class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.references :company,    null: false, foreign_key: true
      t.integer    :parent_id
      t.string     :name,       null: false
      t.string     :code
      t.integer    :sort_order, default: 0
      t.boolean    :active,     null: false, default: true

      t.timestamps
    end
    add_index :departments, [ :company_id, :name ]
    add_index :departments, :parent_id
  end
end
