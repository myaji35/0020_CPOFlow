# frozen_string_literal: true

class EcountSyncLog < ApplicationRecord
  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }

  validates :sync_type, presence: true,
                        inclusion: { in: %w[products customers slip] }

  scope :recent,       -> { order(created_at: :desc) }
  scope :failed_today, -> { where(status: :failed).where("created_at >= ?", Time.current.beginning_of_day) }

  def duration_seconds
    return nil unless started_at && completed_at
    (completed_at - started_at).round(1)
  end
end
