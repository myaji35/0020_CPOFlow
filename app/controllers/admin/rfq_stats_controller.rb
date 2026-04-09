# frozen_string_literal: true

module Admin
  # Phase E: RFQ AI 학습 통계 API
  # GET /admin/rfq_stats           → HTML 대시보드
  # GET /admin/rfq_stats.json      → JSON API (정확도/일치율/평균 score)
  class RfqStatsController < ApplicationController
    before_action :require_manager!

    def index
      window = params[:window].presence&.to_i || 7
      window = 7 if window <= 0 || window > 365
      @stats = Gmail::RfqFeedbackService.accuracy_stats(window_days: window)

      # --- classify_v2 Shadow Mode 카드 3개 (ISS-045 Phase C4) ---
      load_classify_v2_metrics

      respond_to do |format|
        format.html
        format.json { render json: @stats }
      end
    end

    private

    def load_classify_v2_metrics
      today_scope = ClassificationLog.v2.where("created_at >= ?", Time.current.beginning_of_day)

      # 카드 1: 오늘 v2 분류 비용 (USD)
      @classify_cost_today = today_scope.sum(:cost_usd).to_f.round(4)

      # 카드 2: 최근 24h Stage 분기율 (1/2/3)
      last_24h = ClassificationLog.v2.where("created_at >= ?", 24.hours.ago)
      counts = last_24h.group(:stage_reached).count
      total = counts.values.sum
      @stage_distribution = {
        total: total,
        stage0: counts[0].to_i, stage1: counts[1].to_i,
        stage2: counts[2].to_i, stage3: counts[3].to_i,
        stage1_pct: total.zero? ? 0 : (counts[1].to_i * 100.0 / total).round(1),
        stage2_pct: total.zero? ? 0 : (counts[2].to_i * 100.0 / total).round(1),
        stage3_pct: total.zero? ? 0 : (counts[3].to_i * 100.0 / total).round(1)
      }

      # 카드 3: 최근 7일 FN 건수 (would_exclude=true AND Order.rfq_status=rfq_triage)
      fn_scope = ClassificationLog.v2.shadow_would_exclude
                   .where("created_at >= ?", 7.days.ago)
                   .where.not(order_id: nil)
                   .joins(:order)
                   .where(orders: { rfq_status: Order.rfq_statuses[:rfq_triage] })
      @recent_fn_count = fn_scope.count

      # ISS-058: CostGuard 상태
      @cost_guard = Gmail::CostGuard.status
    rescue StandardError => e
      Rails.logger.warn "[Admin::RfqStats] classify_v2 metrics load failed: #{e.class} — #{e.message}"
      @classify_cost_today = 0.0
      @stage_distribution = { total: 0, stage0: 0, stage1: 0, stage2: 0, stage3: 0,
                              stage1_pct: 0, stage2_pct: 0, stage3_pct: 0 }
      @recent_fn_count = 0
      @cost_guard = { today_cost: 0.0, budget: 0.35, exceeded: false, utilization_pct: 0 }
    end
  end
end
