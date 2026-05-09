# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  # ISS-353 Phase 1: 멘션 도트 시스템 상수
  MENTIONED_TYPE = "mentioned"
  STATE_UNREAD = "unread"
  STATE_VIEWED_ONLY = "viewed_only"
  STATE_ACKNOWLEDGED = "acknowledged"
  STATE_SLA_OVERDUE = "sla_overdue"

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  # ISS-353 Phase 1: 멘션 전용 스코프
  scope :mentions,       -> { where(notification_type: MENTIONED_TYPE) }
  scope :unacknowledged, -> { where(acknowledged_at: nil) }
  scope :unviewed,       -> { where(viewed_at: nil) }

  TYPES = %w[
    due_date status_changed assigned system mentioned
    visa contract overdue_escalation ecount_slip_failed oauth_signup
    due_date_risk role_promoted
  ].freeze

  validates :notification_type, presence: true

  # ISS-353 Phase 1: intent_level 기본값 0 (FYI)
  before_validation -> { self.intent_level ||= 0 }

  # ISS-353 Phase 1: 멘션 변경 시 Order 카운터 캐시 동기화
  # B3 결정 (eng-review 2026-05-09): destroy 제외 — destroyed_by_association 가드
  after_commit :sync_order_mention_summary, on: %i[create update]

  # 실 DB free-text type → 표시 카테고리 매핑
  CATEGORY_MAP = {
    /^visa_/              => "visa",
    /^contract_/          => "contract",
    /^due_date_d\d+$/     => "due_date",
    "due_date_risk"       => "due_date",
    "role_promoted"       => "role_promoted",
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
    "role_promoted"    => "권한 변경",
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

  # ISS-353 Phase 1 — 멘션 상태 조회/변경
  def acknowledged?
    acknowledged_at.present?
  end

  def viewed?
    viewed_at.present?
  end

  def mention?
    notification_type == MENTIONED_TYPE
  end

  # 명시적 [✓ 확인] 클릭 — 본인 소유 멘션만, 멱등
  def acknowledge!(viewer:)
    return if acknowledged?
    return unless user_id == viewer.id
    update!(acknowledged_at: Time.current, read_at: read_at || Time.current)
  end

  # 뷰포트 5초 노출 자동 기록 — 1회만 기록 (멱등)
  def mark_viewed!(duration_sec:)
    return if viewed?
    update!(
      viewed_at: Time.current,
      viewed_duration_sec: duration_sec
    )
  end

  private

  # ISS-353 Phase 1: 멘션 알림 변경 시 Order 카운터 캐시 재계산 + Turbo broadcast
  # - B3 가드: dependent: :destroy 연쇄 destroy 시 무발화 (on: %i[create update]로도 1차 차단)
  # - B1-b 결정: broadcast는 stateless (viewer: nil) — 클라이언트가 viewer-self 마킹
  def sync_order_mention_summary
    return if destroyed_by_association.present?
    return unless notification_type == MENTIONED_TYPE
    return unless notifiable.is_a?(Order)

    notifiable.recompute_mention_summary!
    Turbo::StreamsChannel.broadcast_replace_to(
      "order_#{notifiable.id}_mentions",
      target: "mention-dot-strip-#{notifiable.id}",
      partial: "orders/mention_dot_strip",
      locals: { order: notifiable, viewer: nil, variant: :kanban_card }
    )
  rescue StandardError => e
    Rails.logger.warn "[Notification#sync_order_mention_summary] #{e.class}: #{e.message}"
  end
end
