# frozen_string_literal: true

# ISS-352: admin이 직원 환경을 새 탭으로 보기 위한 단기 토큰
# 토큰은 60초 유효, 1회 사용 후 폐기
class ImpersonationToken < ApplicationRecord
  belongs_to :admin,       class_name: "User"
  belongs_to :target_user, class_name: "User"

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :valid, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(admin:, target_user:)
    create!(
      token:       SecureRandom.urlsafe_base64(32),
      admin:       admin,
      target_user: target_user,
      expires_at:  60.seconds.from_now
    )
  end

  def consume!
    update!(used_at: Time.current)
  end

  def valid_token?
    used_at.nil? && expires_at > Time.current
  end
end
