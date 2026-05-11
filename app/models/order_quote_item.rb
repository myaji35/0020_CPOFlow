# frozen_string_literal: true

class OrderQuoteItem < ApplicationRecord
  belongs_to :order
  belongs_to :source_attachment, class_name: "ActiveStorage::Attachment", optional: true
  belongs_to :edited_by_user, class_name: "User", optional: true

  validates :row_no, presence: true,
                     numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(:row_no) }
end
