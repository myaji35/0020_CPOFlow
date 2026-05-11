class AddCascadeToAqaAttachmentFk < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :attachment_quote_analyses, :active_storage_attachments
    add_foreign_key :attachment_quote_analyses, :active_storage_attachments,
                    on_delete: :cascade
  end
end
