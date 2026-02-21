class Client < ApplicationRecord
  has_many :projects,        dependent: :destroy
  has_many :orders,          dependent: :nullify
  has_many :contact_persons, as: :contactable, dependent: :destroy

  INDUSTRIES = %w[nuclear hydro tunnel gtx construction general].freeze
  CREDIT_GRADES = %w[A B C D].freeze
  PAYMENT_TERMS = %w[NET30 NET60 NET90 COD Advance].freeze

  validates :name, :code, :country, presence: true
  validates :code, uniqueness: true
  validates :industry, inclusion: { in: INDUSTRIES, allow_blank: true }
  validates :credit_grade, inclusion: { in: CREDIT_GRADES, allow_blank: true }

  scope :active,  -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  def primary_contact      = contact_persons.find_by(primary: true) || contact_persons.first
  def total_order_value    = orders.sum(:estimated_value).to_f
  def active_orders_count  = orders.where.not(status: :delivered).count
  def active_projects      = projects.where(status: 1)
  def industry_label
    { "nuclear" => "원전", "hydro" => "수력", "tunnel" => "터널",
      "gtx" => "GTX", "construction" => "건설", "general" => "일반" }[industry] || industry
  end
end
