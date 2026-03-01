class CreateJobTitles < ActiveRecord::Migration[8.1]
  def change
    create_table :job_titles do |t|
      t.string  :name,       null: false
      t.integer :sort_order, default: 0
      t.boolean :active,     default: true, null: false

      t.timestamps
    end

    add_index :job_titles, :name, unique: true
    add_index :job_titles, :active
  end
end
