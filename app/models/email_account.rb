class EmailAccount < ApplicationRecord
  belongs_to :user

  # Encrypt OAuth tokens at rest using Lockbox (AES-256-GCM)
  encrypts :gmail_access_token
  encrypts :gmail_refresh_token

  validates :email, presence: true, uniqueness: { scope: :user_id }

  GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.modify"
  ].freeze

  def synced_recently?
    last_synced_at.present? && last_synced_at > 10.minutes.ago
  end

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def needs_refresh?
    gmail_refresh_token.present? && token_expired?
  end

  def ready?
    connected? && gmail_access_token.present?
  end

  def mark_synced!
    update_column(:last_synced_at, Time.current)
  end
end
