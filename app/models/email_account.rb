class EmailAccount < ApplicationRecord
  belongs_to :user

  # Encrypt OAuth tokens at rest using Lockbox (AES-256-GCM)
  # DB columns: gmail_access_token_ciphertext, gmail_refresh_token_ciphertext
  has_encrypted :gmail_access_token
  has_encrypted :gmail_refresh_token

  validates :email, presence: true, uniqueness: { scope: :user_id }

  GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.modify"
  ].freeze

  def synced_recently?
    last_synced_at.present? && last_synced_at > 10.minutes.ago
  end

  def token_expired?
    # access_token이 없거나 만료 시각이 지났으면 만료로 판단
    gmail_access_token.blank? || token_expires_at.blank? || token_expires_at <= Time.current
  end

  def needs_refresh?
    # refresh_token이 있고 access_token이 만료(또는 없음)이면 갱신 필요
    gmail_refresh_token.present? && token_expired?
  end

  def ready?
    # 연결됨 + (access_token 있거나 refresh로 갱신 가능)
    connected? && (gmail_access_token.present? || needs_refresh?)
  end

  def mark_synced!
    update_column(:last_synced_at, Time.current)
  end
end
