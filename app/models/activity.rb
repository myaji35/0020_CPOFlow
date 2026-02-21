class Activity < ApplicationRecord
  belongs_to :order
  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }

  def status_changed?
    from_status.present? && to_status.present?
  end

  def from_label
    Order::STATUS_LABELS[Order.statuses.key(from_status)] if from_status
  end

  def to_label
    Order::STATUS_LABELS[Order.statuses.key(to_status)] if to_status
  end
end
