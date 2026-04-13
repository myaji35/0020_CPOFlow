# frozen_string_literal: true

# ISS-045 Plan §8 Day 3 자동 중단 게이트 (ISS-057)
#
# Shadow Mode 운영 3일차에 rake task(classify_v2:day3_check)가 호출.
# 4가지 임계값을 검증하여 하나라도 초과 시 "failed" 상태로 중단 시그널을 낸다:
#
#   1) 일 평균 비용 > $0.35 → FAIL
#   2) Sonnet 에스컬레이션 비율 > 50% → FAIL
#   3) v1 ↔ v2 verdict 불일치율 > 10% → FAIL
#      v1 proxy = 사용자의 실제 액션(Order.rfq_status):
#        rfq_triage   → "confirmed"
#        rfq_excluded → "excluded"
#        기타(pending 등) → 집계 제외 (사용자 액션 없음)
#   4) safety_fallback 비율 > 5% → FAIL (reason LIKE 'safety_fallback%')
#
# 실제 EmailSyncJob 진입 가드(CostGuard)는 별도 이슈(ISS-058)에서 처리.
# 본 서비스는 계측/보고만 수행.
class ClassifyV2Day3Gate
  COST_THRESHOLD      = 0.35   # USD / day
  SONNET_RATIO_MAX    = 0.50
  DISAGREEMENT_MAX    = 0.10
  SAFETY_FALLBACK_MAX = 0.05

  def initialize(window_days: 3, now: Time.current)
    @window_days = window_days
    @now         = now
    @since       = (now - window_days.days).beginning_of_day
  end

  def run
    checks = [
      check_daily_cost,
      check_sonnet_ratio,
      check_v1_v2_disagreement,
      check_safety_fallback_ratio
    ]
    failures = checks.select { |c| c[:failed] }
    {
      status:      failures.empty? ? "passed" : "failed",
      checked_at:  @now.iso8601,
      window_days: @window_days,
      checks:      checks,
      failures:    failures
    }
  end

  private

  def v2_scope
    ClassificationLog.v2.where("created_at >= ?", @since)
  end

  def check_daily_cost
    total     = v2_scope.sum(:cost_usd).to_f
    daily_avg = total / [ @window_days, 1 ].max
    failed    = daily_avg > COST_THRESHOLD
    {
      name:      "daily_cost_usd",
      actual:    daily_avg.round(4),
      threshold: COST_THRESHOLD,
      failed:    failed,
      reason:    failed ? "일 평균 비용 초과 (총 $#{total.round(4)} / #{@window_days}일)" : nil
    }
  end

  def check_sonnet_ratio
    total = v2_scope.count
    return neutral("sonnet_escalation_ratio", 0.0, SONNET_RATIO_MAX, "no logs") if total.zero?

    sonnet = v2_scope.where(stage_reached: 3).count
    ratio  = sonnet.to_f / total
    failed = ratio > SONNET_RATIO_MAX
    {
      name:      "sonnet_escalation_ratio",
      actual:    ratio.round(4),
      threshold: SONNET_RATIO_MAX,
      failed:    failed,
      reason:    failed ? "Sonnet 호출 #{sonnet}/#{total} 과다 (Stage 1 화이트리스트 확장 검토)" : nil
    }
  end

  # v1 proxy: 사용자의 실제 액션(rfq_status)을 v1 ground truth로 취급.
  #   rfq_triage   → confirmed (사용자가 견적으로 이동)
  #   rfq_excluded → excluded  (사용자가 삭제)
  # v2 verdict와 비교하여 불일치율 산출.
  def check_v1_v2_disagreement
    logs_with_order = v2_scope.where.not(order_id: nil).includes(:order)

    total         = 0
    disagreements = 0
    logs_with_order.find_each do |log|
      order = log.order
      next unless order

      user_verdict = case order.rfq_status.to_s
      when "rfq_triage"   then "confirmed"
      when "rfq_excluded" then "excluded"
      else
                       next # pending 등은 집계 제외 (사용자 액션 없음)
      end

      total += 1
      disagreements += 1 if user_verdict != log.verdict.to_s
    end

    return neutral("v1_v2_disagreement_ratio", 0.0, DISAGREEMENT_MAX, "no labeled logs") if total.zero?

    ratio  = disagreements.to_f / total
    failed = ratio > DISAGREEMENT_MAX
    {
      name:      "v1_v2_disagreement_ratio",
      actual:    ratio.round(4),
      threshold: DISAGREEMENT_MAX,
      failed:    failed,
      reason:    failed ? "v1(사용자 액션) ↔ v2 불일치 #{disagreements}/#{total}" : nil
    }
  end

  def check_safety_fallback_ratio
    total = v2_scope.count
    return neutral("safety_fallback_ratio", 0.0, SAFETY_FALLBACK_MAX, "no logs") if total.zero?

    fallback_count = v2_scope.where("reason LIKE ?", "safety_fallback%").count
    ratio          = fallback_count.to_f / total
    failed         = ratio > SAFETY_FALLBACK_MAX
    {
      name:      "safety_fallback_ratio",
      actual:    ratio.round(4),
      threshold: SAFETY_FALLBACK_MAX,
      failed:    failed,
      reason:    failed ? "safety_fallback #{fallback_count}/#{total} — API 안정성 점검 필요" : nil
    }
  end

  def neutral(name, actual, threshold, reason)
    { name: name, actual: actual, threshold: threshold, failed: false, reason: reason }
  end
end
