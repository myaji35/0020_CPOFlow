# frozen_string_literal: true

module CpoAgent
  class PriceComparisonAnalyzer
    THRESHOLD_PCT = 15  # ±15% 이상이면 Warning

    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id && @order.estimated_value.to_f > 0

      past_orders = Order.where(supplier_id: @order.supplier_id)
                         .where.not(id: @order.id)
                         .where.not(estimated_value: [ nil, 0 ])
                         .order(created_at: :desc)
                         .limit(10)

      return nil if past_orders.count < 2

      avg_value = past_orders.average(:estimated_value).to_f
      current   = @order.estimated_value.to_f
      diff_pct  = ((current - avg_value) / avg_value * 100).round(1)

      return nil if diff_pct.abs < THRESHOLD_PCT

      severity  = diff_pct > 30 ? :alert : :warning
      direction = diff_pct > 0 ? "높습니다" : "낮습니다"

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :price_comparison,
        attrs: {
          severity: severity,
          supplier: @order.supplier,
          title: "단가가 평균 대비 #{diff_pct.abs}% #{direction}",
          body: "이 거래처의 최근 #{past_orders.count}건 평균 금액: $#{'%.0f' % avg_value} → 현재: $#{'%.0f' % current}",
          metadata: {
            avg_value: avg_value.round(2),
            current_value: current,
            diff_pct: diff_pct,
            sample_count: past_orders.count
          },
          expires_at: 7.days.from_now
        }
      )
    end
  end
end
