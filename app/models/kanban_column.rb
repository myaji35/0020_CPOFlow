# frozen_string_literal: true

class KanbanColumn < ApplicationRecord
  belongs_to :kanban_board
  has_many :orders, dependent: :nullify

  validates :key, presence: true, format: { with: /\A[a-z0-9_]+\z/ },
            uniqueness: { scope: :kanban_board_id }
  validates :name, presence: true, length: { maximum: 40 }

  before_validation :generate_key_from_name, if: -> { key.blank? && name.present? }

  scope :ordered, -> { order(:position) }

  private

  def generate_key_from_name
    base = name.to_s.downcase.gsub(/[^a-z0-9\s]/, "").squish.gsub(/\s+/, "_").first(30)
    base = base.gsub(/\A_+|_+\z/, "")
    base = "col_#{SecureRandom.hex(3)}" if base.blank?
    candidate = base
    counter = 1
    while KanbanColumn.where(kanban_board_id: kanban_board_id, key: candidate).where.not(id: id).exists?
      candidate = "#{base}_#{counter}"
      counter += 1
    end
    self.key = candidate
  end
end
