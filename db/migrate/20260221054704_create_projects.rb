class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :client,        null: false, foreign_key: true
      t.string  :name,             null: false
      t.string  :code
      t.string  :site_category
      t.string  :location
      t.string  :country,          default: "AE"
      t.decimal :budget,           precision: 15, scale: 2
      t.string  :currency,         default: "USD"
      t.date    :start_date
      t.date    :end_date
      t.integer :status,           default: 0
      t.text    :description
      t.boolean :active,           default: true, null: false

      t.timestamps
    end

    add_index :projects, :code
    add_index :projects, :site_category
    add_index :projects, :status
  end
end
