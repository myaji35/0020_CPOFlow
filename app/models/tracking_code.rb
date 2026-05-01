class TrackingCode < ApplicationRecord
  has_many :tracking_numbers, dependent: :destroy

  validates :code,        presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 3 }
  validates :short_label, presence: true, length: { maximum: 2 }
  validates :color,       presence: true
  validates :position,    presence: true, numericality: { only_integer: true }

  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:position, :id) }

  before_validation :upcase_code

  private

  def upcase_code
    self.code = code.to_s.upcase if code.present?
    self.short_label = short_label.to_s.upcase if short_label.present?
  end
end
