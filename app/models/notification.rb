# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  TYPES = %w[due_date status_changed assigned system].freeze

  def read?
    read_at.present?
  end

  def read!
    update!(read_at: Time.current) unless read?
  end
end
