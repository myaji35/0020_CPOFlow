# frozen_string_literal: true

# RFQ confirmed 판정 시 답변 초안 자동 생성 (백그라운드)
class RfqReplyDraftJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order

    Gmail::RfqReplyDraftService.generate!(order)
    Rails.logger.info "[RfqReplyDraftJob] Generated reply draft for order ##{order_id}"
  rescue => e
    Rails.logger.error "[RfqReplyDraftJob] Error for order ##{order_id}: #{e.message}"
  end
end
