# frozen_string_literal: true

class AgentTrustLevel < ApplicationRecord
  belongs_to :user

  TRUST_THRESHOLD = 5

  validates :insight_type, presence: true
  validates :user_id, uniqueness: { scope: :insight_type }

  def self.record_feedback!(user:, insight_type:, useful:)
    level = find_or_create_by(user: user, insight_type: insight_type)
    if useful
      level.increment!(:useful_count)
      if level.useful_count >= TRUST_THRESHOLD && !level.auto_mode
        level.update!(auto_mode: true, auto_activated_at: Time.current)
      end
    else
      level.increment!(:dismiss_count)
    end
    level
  end

  def self.auto_mode?(user:, insight_type:)
    find_by(user: user, insight_type: insight_type)&.auto_mode || false
  end
end
