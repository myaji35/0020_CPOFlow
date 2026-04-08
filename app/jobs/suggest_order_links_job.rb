# Procurement Ontology M3 — Heuristic 제안 Job
#
# 2종 heuristic으로 OrderLink suggested 자동 생성:
#   1. same_client_recent — 같은 Client + 90일 내 → confidence 0.7
#   2. reference_no_pattern — 같은 prefix(앞 2 토큰) → confidence 0.6
#
# 트리거: Order.after_create_commit { SuggestOrderLinksJob.perform_later(id) }
# 멱등성: find_or_create_by! 로 중복 방지.
class SuggestOrderLinksJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order
    suggest_by_same_client_recent(order)
    suggest_by_reference_no_pattern(order)
  end

  private

  def suggest_by_same_client_recent(order)
    return if order.client_id.blank?
    Order.where(client_id: order.client_id)
         .where.not(id: order.id)
         .where("created_at > ?", 90.days.ago)
         .limit(5)
         .find_each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.7
        l.metadata = { source: "heuristic", trigger: "same_client_recent" }
      end
    end
  end

  def suggest_by_reference_no_pattern(order)
    return if order.reference_no.blank?
    parts = order.reference_no.split("-")
    return if parts.size < 2
    prefix = parts.first(2).join("-")
    Order.where("reference_no LIKE ?", "#{prefix}-%")
         .where.not(id: order.id)
         .where.not(reference_no: order.reference_no)
         .limit(5)
         .find_each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.6
        l.metadata = { source: "heuristic", trigger: "reference_no_pattern", prefix: prefix }
      end
    end
  end
end
