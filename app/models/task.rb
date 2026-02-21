class Task < ApplicationRecord
  belongs_to :order
  belongs_to :assignee, class_name: "User", optional: true

  validates :title, presence: true

  scope :pending, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
  scope :by_due, -> { order(due_date: :asc, created_at: :asc) }

  def overdue?
    !completed && due_date.present? && due_date < Date.today
  end
end
