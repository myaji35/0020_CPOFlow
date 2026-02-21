class CreateImportLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :import_logs do |t|
      t.string :source
      t.string :filename
      t.integer :status
      t.integer :total_rows
      t.integer :success_rows
      t.integer :error_rows
      t.text :error_details
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
