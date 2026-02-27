# frozen_string_literal: true

# Order confirmed → eCountERP 매출 전표 자동 생성 Job
# Order 모델의 after_update_commit 콜백에서 enqueue됨
class EcountSlipCreateJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    result = EcountApi::SlipCreateService.new(order).create!

    if result[:ok]
      if result[:skipped]
        Rails.logger.info "[EcountSlipCreateJob] Order##{order_id} 스킵 (이미 전표 있음)"
      else
        Rails.logger.info "[EcountSlipCreateJob] Order##{order_id} 전표 생성: #{result[:slip_no]}"
      end
    else
      Rails.logger.error "[EcountSlipCreateJob] Order##{order_id} 전표 생성 실패: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[EcountSlipCreateJob] Order##{order_id} 없음 — 스킵"
  end
end
