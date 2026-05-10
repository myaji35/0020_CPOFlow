# frozen_string_literal: true

# ISS-354 Phase 2 Wave 1 — T4
# 시간 경과로 SLA 초과된 멘션 카드의 worst_state/worst_intent 캐시를 갱신한다.
#
# Notification#sync_order_mention_summary 는 알림 *변경* 시에만 발화하므로,
# 시간만 흘러서 sla_due_at < now 가 된 카드는 카운터 캐시가 stale 해진다.
# 이 Job 이 시간당 1회 실행되어 catch-up 한다.
#
# B4 결정 (2026-05-10): 쿼리 윈도우 25시간으로 제한 — 무한 누적 방지.
#   - sla_due_at > 25.hours.ago: 너무 오래된 SLA 는 다음 갱신 사이클에서 이미 처리됨 (idempotent skip)
#   - sla_due_at < Time.current: 마감 경과한 것만
#   - acknowledged_at IS NULL: 아직 응답 안 한 것만
class MentionSlaCheckerJob < ApplicationJob
  queue_as :default

  def perform
    affected_orders = Notification.mentions
                                  .where("sla_due_at > ? AND sla_due_at < ?", 25.hours.ago, Time.current)
                                  .where(acknowledged_at: nil)
                                  .where(notifiable_type: "Order")
                                  .distinct
                                  .pluck(:notifiable_id)

    return if affected_orders.empty?

    Order.where(id: affected_orders).find_each do |order|
      order.recompute_mention_summary!
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_mentions",
        target:  "mention-dot-strip-#{order.id}",
        partial: "orders/mention_dot_strip",
        locals:  { order: order, viewer: nil, variant: :kanban_card }
      )
    rescue StandardError => e
      Rails.logger.warn "[MentionSlaCheckerJob] order##{order.id} 갱신 실패: #{e.class}: #{e.message}"
    end
  end
end
