# ISS-330: 표준 RFP 분석 체크리스트
class ChecklistItem < ApplicationRecord
  CATEGORIES = %w[general quality cert drawing urgency].freeze

  validates :code, presence: true, uniqueness: true, format: { with: /\A[A-Z][A-Z0-9_]*\z/, message: "대문자/숫자/언더스코어만" }
  validates :name, presence: true
  validates :prompt_hint, presence: true
  validates :category, inclusion: { in: CATEGORIES }

  scope :active,        -> { where(active: true) }
  scope :ordered,       -> { order(:position, :code) }
  scope :for_category,  ->(c) { where(category: c) }

  # JSON 배열 직렬화 (allowed_values)
  def allowed_values_array
    return [] if allowed_values.blank?
    JSON.parse(allowed_values)
  rescue JSON::ParserError
    []
  end

  def allowed_values_array=(arr)
    self.allowed_values = arr.present? ? arr.to_json : nil
  end

  # ItemExtractor에 주입할 프롬프트 단편
  def prompt_fragment
    base = "- #{code}: #{prompt_hint}"
    base += " (allowed: #{allowed_values_array.join(', ')})" if allowed_values_array.any?
    base += " [REQUIRED]" if required
    base
  end
end
