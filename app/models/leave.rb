class Leave < ApplicationRecord
  LEAVE_TYPES = %w[annual sick maternity unpaid].freeze
  STATUSES    = %w[requested manager_approved approved rejected cancelled].freeze

  belongs_to :employee
  belongs_to :manager_approved_by, class_name: "User", optional: true
  belongs_to :admin_approved_by,   class_name: "User", optional: true
  belongs_to :rejected_by,         class_name: "User", optional: true

  has_many_attached :documents

  enum :leave_type, LEAVE_TYPES.index_by(&:itself), prefix: false
  enum :status,     STATUSES.index_by(&:itself),    prefix: false

  validates :leave_type,    presence: true, inclusion: { in: LEAVE_TYPES }
  validates :status,        presence: true, inclusion: { in: STATUSES }
  validates :start_date,    presence: true
  validates :end_date,      presence: true
  validates :days_requested, numericality: { greater_than: 0 }
  validate  :end_after_start

  before_save :calculate_days

  scope :pending,  -> { where(status: %w[requested manager_approved]) }
  scope :approved, -> { where(status: "approved") }
  scope :for_employee, ->(emp) { where(employee: emp) }
  scope :this_year, -> { where("start_date >= ? AND start_date <= ?", Date.current.beginning_of_year, Date.current.end_of_year) }
  scope :for_calendar, ->(from, to) { where("start_date <= ? AND end_date >= ?", to, from) }

  def leave_type_label
    I18n.t("leaves.leave_type_#{leave_type}", default: leave_type.capitalize)
  end

  def status_label
    I18n.t("leaves.status_#{status}", default: status.humanize)
  end

  def status_badge_class
    case status
    when "requested"        then "bg-yellow-500 text-white"
    when "manager_approved" then "bg-blue-500 text-white"
    when "approved"         then "bg-green-600 text-white"
    when "rejected"         then "bg-red-600 text-white"
    when "cancelled"        then "bg-gray-400 text-white"
    end
  end

  def leave_type_color
    case leave_type
    when "annual"    then "#00A1E0"
    when "sick"      then "#F4A83A"
    when "maternity" then "#a855f7"
    when "unpaid"    then "#6b7280"
    end
  end

  private

  def end_after_start
    return unless start_date && end_date
    errors.add(:end_date, I18n.t("leaves.errors.end_after_start", default: "종료일은 시작일 이후여야 합니다")) if end_date < start_date
  end

  def calculate_days
    return unless start_date && end_date
    self.days_requested = (end_date - start_date).to_i + 1 if days_requested.nil? || days_requested <= 0
  end
end
