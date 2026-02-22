# frozen_string_literal: true

# 전체 미납품 주문의 위험도를 일괄 재계산하는 배치 Job
# Solid Queue 스케줄러로 매 5분마다 실행 권장
class RiskAssessmentJob < ApplicationJob
  queue_as :default

  def perform
    count = RiskAssessmentService.batch_update!
    Rails.logger.info "[RiskAssessmentJob] Updated #{count} orders"
  end
end
