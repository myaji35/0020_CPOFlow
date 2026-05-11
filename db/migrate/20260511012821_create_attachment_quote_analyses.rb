class CreateAttachmentQuoteAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :attachment_quote_analyses do |t|
      t.references :order, null: false, foreign_key: true, index: false
      t.references :active_storage_attachment, null: false,
                   foreign_key: { to_table: :active_storage_attachments },
                   index: false
      t.string  :status, null: false, default: "pending"
      t.boolean :is_quote_doc, null: false, default: false
      t.text    :items_json
      t.string  :llm_model
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0.0
      t.integer :latency_ms, default: 0
      t.text    :error_message
      t.integer :reanalyzed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :attachment_quote_analyses, :active_storage_attachment_id,
              unique: true, name: "idx_aqa_on_attachment_unique"
    add_index :attachment_quote_analyses, %i[order_id status], name: "idx_aqa_on_order_status"
  end
end
