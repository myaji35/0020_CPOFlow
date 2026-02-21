class CreateContactPersons < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_persons do |t|
      t.references :contactable,   polymorphic: true, null: false
      t.string  :name,             null: false
      t.string  :title
      t.string  :email
      t.string  :phone
      t.string  :whatsapp
      t.string  :wechat
      t.string  :language,         default: "en"
      t.string  :nationality
      t.boolean :primary,          default: false
      t.text    :notes

      t.timestamps
    end

    add_index :contact_persons, [ :contactable_type, :contactable_id ]
    add_index :contact_persons, :email
  end
end
