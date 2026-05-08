# frozen_string_literal: true

# LAB / RFQ Auto — 분석 비동기 실행. Turbo Stream으로 단계별 결과 broadcast.
# Analyzer 자체가 broadcast_progress!를 단계마다 호출하므로 Job은 단순 dispatcher.
class RfqAutoAnalyzeJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    analysis = RfqAutoAnalysis.find(analysis_id)
    return unless analysis.running?

    RfqAuto::Analyzer.new(analysis).call
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "[RfqAutoAnalyzeJob] analysis #{analysis_id} not found: #{e.message}"
  end
end
