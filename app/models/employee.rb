class Employee < ApplicationRecord
  belongs_to :user,       optional: true
  belongs_to :department, optional: true
  has_many :visas,                dependent: :destroy
  has_many :employment_contracts, dependent: :destroy
  has_many :employee_assignments, dependent: :destroy
  has_many :assigned_projects, through: :employee_assignments, source: :project
  has_many :certifications,       dependent: :destroy

  EMPLOYMENT_TYPES = %w[regular contract dispatch].freeze
  NATIONALITIES = {
    "AE" => "UAE", "KR" => "한국", "US" => "미국", "GB" => "영국",
    "IN" => "인도", "PH" => "필리핀", "PK" => "파키스탄", "EG" => "이집트",
    "JP" => "일본", "CN" => "중국", "DE" => "독일", "FR" => "프랑스"
  }.freeze

  validates :name, :nationality, :employment_type, presence: true
  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }

  scope :active,     -> { where(active: true) }
  scope :by_name,    -> { order(:name) }
  scope :dispatched, -> { joins(:employee_assignments).where(employee_assignments: { status: "active" }).distinct }

  def current_contract   = employment_contracts.where(status: "active").order(start_date: :desc).first
  def current_assignment = employee_assignments.where(status: "active").order(start_date: :desc).first
  def active_visa        = visas.where(status: "active").order(expiry_date: :asc).first

  def nationality_label = NATIONALITIES[nationality] || nationality

  def employment_type_label
    { "regular" => "정규직", "contract" => "계약직", "dispatch" => "파견" }[employment_type] || employment_type
  end

  def visa_expiring_soon?
    return false unless active_visa
    active_visa.expiry_date <= 60.days.from_now.to_date
  end

  def contract_expiring_soon?
    return false unless current_contract&.end_date
    current_contract.end_date <= 30.days.from_now.to_date
  end

  def tenure_days
    return nil unless hire_date
    ((termination_date || Date.today) - hire_date).to_i
  end
end
