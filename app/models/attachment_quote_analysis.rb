# frozen_string_literal: true

class AttachmentQuoteAnalysis < ApplicationRecord
  STATUSES = %w[pending running completed failed not_quote].freeze

  belongs_to :order
  belongs_to :active_storage_attachment, class_name: "ActiveStorage::Attachment"

  validates :status, inclusion: { in: STATUSES }
  validates :active_storage_attachment_id, uniqueness: true

  scope :recent, -> { order(updated_at: :desc) }

  def items
    return [] if items_json.blank?
    parsed = JSON.parse(items_json)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
