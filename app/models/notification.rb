# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  TYPES = %w[
    due_date status_changed assigned system mentioned
    visa contract overdue_escalation ecount_slip_failed oauth_signup
    due_date_risk role_promoted
  ].freeze

  validates :notification_type, presence: true

  # 실 DB free-text type → 표시 카테고리 매핑
  CATEGORY_MAP = {
    /^visa_/              => "visa",
    /^contract_/          => "contract",
    /^due_date_d\d+$/     => "due_date",
    "due_date_risk"       => "due_date",
    "role_promoted"       => "system",
    "overdue_unassigned_escalation" => "overdue_escalation",
    /^ecount_slip_failed/ => "ecount_slip_failed",
    "new_oauth_user"      => "oauth_signup"
  }.freeze

  # 카테고리별 한국어 라벨
  CATEGORY_LABELS = {
    "all"              => "전체",
    "mentioned"        => "@멘션",
    "due_date"         => "납기",
    "status_changed"   => "상태변경",
    "assigned"         => "배정",
    "visa"             => "비자",
    "contract"         => "계약",
    "overdue_escalation" => "미배정 에스컬",
    "ecount_slip_failed" => "eCount 오류",
    "oauth_signup"     => "신규 가입",
    "system"           => "시스템"
  }.freeze

  def category
    return "system" if notification_type.nil?

    CATEGORY_MAP.each do |pattern, cat|
      case pattern
      when Regexp then return cat if notification_type.match?(pattern)
      when String then return cat if notification_type == pattern
      end
    end
    # 기본값: notification_type이 알려진 카테고리면 그대로, 아니면 system
    TYPES.include?(notification_type) ? notification_type : "system"
  end

  def read?
    read_at.present?
  end

  def read!
    update!(read_at: Time.current) unless read?
  end
end
