class Order < ApplicationRecord
  belongs_to :user     # creator
  belongs_to :client,   optional: true
  belongs_to :supplier, optional: true
  belongs_to :project,  optional: true
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :assignees, through: :assignments, source: :user

  enum :status, {
    inbox: 0,
    reviewing: 1,
    quoted: 2,
    confirmed: 3,
    procuring: 4,
    qa: 5,
    delivered: 6
  }, default: :inbox

  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, default: :medium

  validates :title, presence: true
  validates :customer_name, presence: true
  validates :status, presence: true

  scope :active, -> { where.not(status: :delivered) }
  scope :overdue, -> { where("due_date < ?", Date.today).where.not(status: :delivered) }
  scope :urgent, -> { where("due_date <= ?", 7.days.from_now).where.not(status: :delivered) }
  scope :due_soon, -> { where(due_date: Date.today..14.days.from_now).where.not(status: :delivered) }
  scope :by_due_date, -> { order(due_date: :asc) }

  KANBAN_COLUMNS = %w[inbox reviewing quoted confirmed procuring qa delivered].freeze

  STATUS_LABELS = {
    "inbox"     => "Inbox",
    "reviewing" => "Under Review",
    "quoted"    => "Quoted",
    "confirmed" => "Order Confirmed",
    "procuring" => "Procuring",
    "qa"        => "QA Inspection",
    "delivered" => "Delivered"
  }.freeze

  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end

  def due_urgency
    days = days_until_due
    return :overdue if days&.negative?
    return :urgent  if days && days <= 7
    return :warning if days && days <= 14
    :normal
  end

  def due_badge_class
    case due_urgency
    when :overdue then "badge-danger"
    when :urgent  then "badge-danger"
    when :warning then "badge-warning"
    else               "badge-success"
    end
  end

  def task_progress
    return { done: 0, total: 0 } if tasks.empty?
    { done: tasks.where(completed: true).count, total: tasks.count }
  end

  def tags_array
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
