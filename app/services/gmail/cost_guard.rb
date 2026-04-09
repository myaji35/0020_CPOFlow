# frozen_string_literal: true

module Gmail
  # ISS-058: classify_v2 일 비용 실시간 차단 게이트
  #
  # Plan §2 목표 $0.30/day, §8 > $0.35 중단.
  # EmailSyncJob 진입점에서 매번 호출하여 금일 v2 누적 비용이 임계를 넘으면
  # Orchestrator 호출을 skip (nil 반환 → EmailToOrderService는 v2_result:nil로 동작).
  #
  # 결과: v2 경로만 차단, 방식 2 (RfqDetectorService + 전수 저장)은 계속 실행.
  # 사용자 화면은 영향 없음 (rfq_pending 유지).
  #
  # Usage:
  #   if Gmail::CostGuard.exceeded?
  #     v2_result = nil
  #   else
  #     v2_result = orchestrator.classify
  #   end
  class CostGuard
    DEFAULT_BUDGET = 0.35   # USD/day, ENV CLASSIFY_V2_DAILY_BUDGET 로 override
    WARN_LOG_CACHE_KEY = "gmail/cost_guard/warned_on"

    def self.today_cost
      ClassificationLog.v2
                       .where("created_at >= ?", Time.current.beginning_of_day)
                       .sum(:cost_usd).to_f
    end

    def self.budget
      ENV.fetch("CLASSIFY_V2_DAILY_BUDGET", DEFAULT_BUDGET).to_f
    end

    def self.exceeded?
      today_cost > budget
    end

    # 하루에 한 번만 Rails.logger.warn (중복 로그 방지)
    def self.warn_once!
      today_key = Date.current.iso8601
      cached = Rails.cache.read(WARN_LOG_CACHE_KEY)
      return if cached == today_key

      Rails.logger.warn(
        "[CostGuard] classify_v2 daily budget exceeded — " \
        "today_cost=$#{today_cost.round(4)} budget=$#{budget} " \
        "v2 path disabled for rest of day; 방식 2 백그라운드는 계속 실행"
      )
      Rails.cache.write(WARN_LOG_CACHE_KEY, today_key, expires_in: 30.hours)
    end

    # 상태 요약 (Admin 카드 / 디버깅용)
    def self.status
      cost = today_cost
      b = budget
      {
        today_cost: cost.round(4),
        budget: b,
        exceeded: cost > b,
        utilization_pct: b.zero? ? 0 : ((cost / b) * 100).round(1)
      }
    end
  end
end
