class Visa < ApplicationRecord
  belongs_to :employee

  VISA_TYPES    = %w[Employment Tourist Transit Residence].freeze
  VISA_STATUSES = %w[active expired pending cancelled].freeze

  validates :visa_type, :issuing_country, :expiry_date, :status, presence: true
  validates :visa_type, inclusion: { in: VISA_TYPES }
  validates :status, inclusion: { in: VISA_STATUSES }

  scope :active,          -> { where(status: "active") }
  scope :by_expiry,       -> { order(expiry_date: :asc) }
  scope :expiring_within, ->(days) { active.where("expiry_date <= ?", days.days.from_now.to_date) }

  def days_until_expiry = (expiry_date - Date.today).to_i

  def expiry_urgency
    days = days_until_expiry
    return :expired  if days < 0
    return :critical if days <= 14
    return :warning  if days <= 30
    return :caution  if days <= 60
    :normal
  end

  def expiry_badge_class
    case expiry_urgency
    when :expired, :critical then "bg-red-50 text-red-700"
    when :warning             then "bg-orange-50 text-orange-700"
    when :caution             then "bg-yellow-50 text-yellow-700"
    else                           "bg-green-50 text-green-700"
    end
  end
end
