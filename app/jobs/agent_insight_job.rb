# frozen_string_literal: true

# CPO Agent 분석 Job — 오더 열람 시 비동기로 실행
class AgentInsightJob < ApplicationJob
  queue_as :default

  def perform(order_id, user_id = nil)
    order = Order.includes(:supplier, :client, :order_quotes).find_by(id: order_id)
    return unless order

    last = order.agent_insights.order(created_at: :desc).first
    return if last && last.created_at > 5.minutes.ago

    insights = CpoAgent::Service.analyze(order)

    # 자동 모드 실행
    user = User.find_by(id: user_id)
    if user
      insights.each do |insight|
        CpoAgent::AutoActionService.execute(order, insight, user)
      end
    end

    Rails.logger.info "[AgentInsightJob] Analyzed order ##{order_id} (auto actions for user ##{user_id})"
  rescue => e
    Rails.logger.error "[AgentInsightJob] Error for order ##{order_id}: #{e.message}"
  end
end
