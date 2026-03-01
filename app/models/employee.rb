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
  AVATAR_COLORS = {
    "KR" => "bg-blue-500",   "AE" => "bg-emerald-500", "PH" => "bg-yellow-500",
    "IN" => "bg-orange-500", "PK" => "bg-green-600",   "EG" => "bg-amber-600",
    "US" => "bg-indigo-500", "GB" => "bg-violet-500",  "JP" => "bg-rose-500",
    "CN" => "bg-red-500",    "DE" => "bg-cyan-600",    "FR" => "bg-purple-500"
  }.freeze

  validates :name, :nationality, :employment_type, presence: true
  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }

  scope :active,     -> { where(active: true) }
  scope :by_name,    -> { order(:name) }
  scope :dispatched, -> { joins(:employee_assignments).where(employee_assignments: { status: "active" }).distinct }

  def current_contract   = employment_contracts.where(status: "active").order(start_date: :desc).first
  def current_assignment = employee_assignments.where(status: "active").order(start_date: :desc).first
  def active_visa        = visas.where(status: "active").order(expiry_date: :asc).first
  def current_project    = current_assignment&.project

  def display_name = name
  def initials = name.split.map(&:first).first(2).join.upcase
  def avatar_color = AVATAR_COLORS[nationality] || "bg-gray-500"

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

  def tenure_label
    return nil unless hire_date
    total = tenure_days
    years  = total / 365
    months = (total % 365) / 30
    if years > 0
      "#{years}년 #{months}개월"
    elsif months > 0
      "#{months}개월"
    else
      "#{total}일"
    end
  end
end
