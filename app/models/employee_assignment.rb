class EmployeeAssignment < ApplicationRecord
  belongs_to :employee
  belongs_to :project

  ASSIGNMENT_STATUSES = %w[active completed cancelled].freeze

  validates :start_date, :status, presence: true
  validates :status, inclusion: { in: ASSIGNMENT_STATUSES }

  scope :active,   -> { where(status: "active") }
  scope :by_start, -> { order(start_date: :desc) }

  def status_label
    { "active" => "배정중", "completed" => "완료", "cancelled" => "취소" }[status] || status
  end

  def status_badge_class
    case status
    when "active"    then "bg-green-50 text-green-700"
    when "completed" then "bg-gray-100 text-gray-600"
    when "cancelled" then "bg-red-50 text-red-700"
    else "bg-gray-100 text-gray-600"
    end
  end
end
