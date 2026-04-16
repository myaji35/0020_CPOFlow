# frozen_string_literal: true

class CardStatus < ApplicationRecord
  HEX_COLOR = /\A#[0-9A-Fa-f]{6}\z/.freeze

  belongs_to :kanban_board, optional: true
  has_many :orders, dependent: :restrict_with_error

  before_validation :generate_key_from_name, if: -> { key.blank? && name.present? }

  validates :key,          presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name,         presence: true, length: { maximum: 40 }
  validates :bg_color,     :border_color, :text_color,
                           presence: true, format: { with: HEX_COLOR, message: "must be #RRGGBB format" }
  validates :auto_priority, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :id) }

  def self.default
    find_by(is_default: true) || ordered.first
  end

  def deletable?
    !is_system? && orders.empty?
  end

  # auto_rule JSON 파싱 (예: {"when":"due_date","operator":"lte","value":3})
  def parsed_auto_rule
    return nil if auto_rule.blank?
    JSON.parse(auto_rule)
  rescue JSON::ParserError
    nil
  end

  # 현재 Order에 이 상태의 auto_rule이 적용되는지 판정
  def auto_applies_to?(order)
    rule = parsed_auto_rule
    return false unless rule
    case rule["when"]
    when "due_date"
      return false unless order.due_date
      days = (order.due_date - Date.current).to_i
      case rule["operator"]
      when "lte" then days <= rule["value"].to_i
      when "gte" then days >= rule["value"].to_i
      else false
      end
    else
      false
    end
  end

  private

  def generate_key_from_name
    base = name.to_s.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "_").first(30)
    base = "status_#{SecureRandom.hex(3)}" if base.blank?
    candidate = base
    counter = 1
    while CardStatus.where(key: candidate).where.not(id: id).exists?
      candidate = "#{base}_#{counter}"
      counter += 1
    end
    self.key = candidate
  end
end
