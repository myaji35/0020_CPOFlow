class EmploymentContract < ApplicationRecord
  belongs_to :employee
  belongs_to :project, optional: true

  PAY_FREQUENCIES   = %w[monthly bi-monthly weekly].freeze
  CONTRACT_STATUSES = %w[active expired terminated renewed].freeze

  validates :start_date, :status, presence: true
  validates :status, inclusion: { in: CONTRACT_STATUSES }

  scope :active,          -> { where(status: "active") }
  scope :by_start,        -> { order(start_date: :desc) }
  scope :expiring_within, ->(days) { active.where("end_date IS NOT NULL AND end_date <= ?", days.days.from_now.to_date) }

  def pay_frequency_label
    { "monthly" => "월급", "bi-monthly" => "격월", "weekly" => "주급" }[pay_frequency] || pay_frequency
  end

  def status_label
    { "active" => "계약중", "expired" => "만료", "terminated" => "해지", "renewed" => "갱신됨" }[status] || status
  end

  def status_badge_class
    case status
    when "active"   then "bg-green-50 text-green-700"
    when "expired"  then "bg-gray-100 text-gray-600"
    when "terminated" then "bg-red-50 text-red-700"
    when "renewed"  then "bg-blue-50 text-blue-700"
    else "bg-gray-100 text-gray-600"
    end
  end
end
