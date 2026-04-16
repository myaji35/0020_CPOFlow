# frozen_string_literal: true

class KanbanBoard < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
  has_many :card_statuses, -> { order(:position) }, dependent: :nullify
  has_many :orders, dependent: :nullify

  validates :name, presence: true, length: { maximum: 50 }
  validates :board_type, inclusion: { in: %w[purchase sales project custom] }
  validates :color_palette, inclusion: { in: %w[pastel vivid mono corporate] }

  scope :ordered, -> { order(:position) }
  scope :default_board, -> { where(is_default: true) }

  def self.ensure_default!
    return first if exists?(is_default: true)
    create!(name: "구매보드", board_type: "purchase", is_default: true, position: 0)
  end
end
