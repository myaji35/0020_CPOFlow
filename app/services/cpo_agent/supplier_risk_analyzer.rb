# frozen_string_literal: true

module CpoAgent
  class SupplierRiskAnalyzer
    DELIVERY_RATE_THRESHOLD = 80  # 80% 미만이면 Alert

    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id
      supplier = @order.supplier

      total = supplier.orders.where(status: :get_grn).count
      return nil if total < 3

      on_time = supplier.orders.where(status: :get_grn)
                        .where("due_date IS NOT NULL AND updated_at <= due_date + 1")
                        .count
      rate = (on_time.to_f / total * 100).round(1)

      grade_risk = %w[C D].include?(supplier.credit_grade)

      return nil if rate >= DELIVERY_RATE_THRESHOLD && !grade_risk

      severity = rate < 60 || supplier.credit_grade == "D" ? :alert : :warning

      title_parts = []
      title_parts << "납기 준수율 #{rate}%" if rate < DELIVERY_RATE_THRESHOLD
      title_parts << "신용등급 #{supplier.credit_grade}" if grade_risk

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :supplier_risk,
        attrs: {
          severity: severity,
          supplier: supplier,
          title: "거래처 주의: #{title_parts.join(' / ')}",
          body: "#{supplier.name} — 총 #{total}건 중 #{on_time}건 정시 납품",
          metadata: {
            delivery_rate: rate,
            total_orders: total,
            on_time_orders: on_time,
            credit_grade: supplier.credit_grade
          },
          expires_at: 3.days.from_now
        }
      )
    end
  end
end
