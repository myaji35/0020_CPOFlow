# frozen_string_literal: true

# CPO Agent 분석 Job — 오더 열람 시 비동기로 실행
class AgentInsightJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.includes(:supplier, :client, :order_quotes).find_by(id: order_id)
    return unless order

    # 최근 5분 내 분석했으면 건너뛰기 (드로어 열 때마다 실행 방지)
    last = order.agent_insights.order(created_at: :desc).first
    return if last && last.created_at > 5.minutes.ago

    CpoAgent::Service.analyze(order)
    Rails.logger.info "[AgentInsightJob] Analyzed order ##{order_id}"
  rescue => e
    Rails.logger.error "[AgentInsightJob] Error for order ##{order_id}: #{e.message}"
  end
end
