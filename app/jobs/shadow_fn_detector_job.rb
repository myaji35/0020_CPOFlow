# frozen_string_literal: true

# ISS-045 Phase C4: Shadow Mode False Negative 감지
#
# v2 ClassificationOrchestrator가 would_exclude=true 로 판정한 classification_logs 중,
# 해당 Order가 현재 rfq_status="rfq_triage" (=사용자가 bulk_to_kanban 으로 확정) 인 것은
# v2의 False Negative. 2026-03 KEPCO 견적 누락 사고 재발 방지의 핵심 시그널.
#
# 실행: 매일 02:00 (config/recurring.yml)
# 동작: 최근 24h 범위 would_exclude=true 레코드 순회 → FN 카운트 로깅 + Rails.logger.error
# (ISS-036 Google Chat 알림 경로는 BLOCKED이므로 log-only. 추후 경로 복구 시 이 Job에 알림 hook 추가)
class ShadowFnDetectorJob < ApplicationJob
  queue_as :default

  def perform(window_hours: 24)
    since = window_hours.hours.ago
    suspects = ClassificationLog
                 .v2
                 .shadow_would_exclude
                 .where("created_at >= ?", since)
                 .where.not(order_id: nil)

    fn_count = 0
    suspects.find_each do |log|
      order = log.order
      next unless order
      # 사용자가 bulk_to_kanban으로 rfq_triage 처리 = v2가 놓칠 뻔한 것
      if order.rfq_status == "rfq_triage"
        fn_count += 1
        Rails.logger.error(
          "[ShadowFnDetector] FN detected — Order##{order.id} " \
          "email_message_id=#{log.email_message_id} " \
          "v2_verdict=excluded v2_reason=#{log.reason} " \
          "user_verdict=rfq_triage"
        )
      end
    end

    Rails.logger.info "[ShadowFnDetector] window=#{window_hours}h suspects=#{suspects.size} fn=#{fn_count}"
    { suspects: suspects.size, fn: fn_count }
  end
end
