class Certification < ApplicationRecord
  belongs_to :employee

  validates :name, presence: true

  scope :by_expiry, -> { order(expiry_date: :asc) }
  scope :expiring_within, ->(days) {
    where("expiry_date IS NOT NULL AND expiry_date <= ?", days.days.from_now.to_date)
  }

  def expired?       = expiry_date.present? && expiry_date < Date.today
  def expiring_soon? = expiry_date.present? && expiry_date <= 30.days.from_now.to_date && !expired?

  def expiry_badge_class
    if expired?        then "bg-red-50 text-red-700"
    elsif expiring_soon? then "bg-yellow-50 text-yellow-700"
    else                    "bg-green-50 text-green-700"
    end
  end
end
