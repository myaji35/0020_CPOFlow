class ExtendImportLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :import_logs, :import_type,      :string,   default: "products", null: false
    add_column :import_logs, :result_file_path, :string
    add_column :import_logs, :completed_at,     :datetime
    add_column :import_logs, :preview_data,     :text

    # Change status from integer enum to string enum for clarity
    # (existing integer values preserved; 0=pending,1=processing,2=completed,3=failed)
    add_index :import_logs, :import_type
    add_index :import_logs, :status
  end
end
