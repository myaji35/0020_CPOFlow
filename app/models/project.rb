class Project < ApplicationRecord
  belongs_to :client
  has_many :orders,               dependent: :nullify
  has_many :employee_assignments, dependent: :destroy
  has_many :employees, through: :employee_assignments

  SITE_CATEGORIES = %w[nuclear hydro tunnel gtx general].freeze
  STATUSES = { "planning" => 0, "active" => 1, "completed" => 2, "suspended" => 3 }.freeze

  enum :status, { planning: 0, active: 1, completed: 2, suspended: 3 }, default: :active

  validates :name, :client, presence: true
  validates :site_category, inclusion: { in: SITE_CATEGORIES, allow_blank: true }

  scope :active,      -> { where(status: :active) }
  scope :by_category, ->(cat) { where(site_category: cat) }
  scope :by_name,     -> { order(:name) }

  def budget_utilized  = orders.sum(:estimated_value).to_f
  def budget_remaining = (budget.to_f) - budget_utilized
  def utilization_rate
    return 0 if budget.to_f.zero?
    ((budget_utilized / budget.to_f) * 100).round(1)
  end

  def site_category_label
    { "nuclear" => "원전", "hydro" => "수력", "tunnel" => "터널",
      "gtx" => "GTX", "general" => "일반" }[site_category] || site_category
  end

  def status_label
    { "planning" => "계획", "active" => "진행중", "completed" => "완료", "suspended" => "중단" }[status] || status
  end
end
