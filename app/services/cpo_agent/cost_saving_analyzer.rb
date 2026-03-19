# frozen_string_literal: true

module CpoAgent
  class CostSavingAnalyzer
    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id && @order.estimated_value.to_f > 0

      cheaper = OrderQuote.joins(:supplier)
                          .where(order_id: Order.where.not(supplier_id: @order.supplier_id)
                                                .where("title LIKE ?", "%#{@order.title.first(20)}%")
                                                .select(:id))
                          .where("unit_price > 0")
                          .order(:unit_price)
                          .limit(3)

      return nil if cheaper.empty?

      best = cheaper.first
      current_price = @order.estimated_value.to_f
      saving = current_price - best.unit_price.to_f
      return nil if saving <= 0

      saving_pct = (saving / current_price * 100).round(1)
      return nil if saving_pct < 5

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :cost_saving,
        attrs: {
          severity: :info,
          supplier: best.supplier,
          title: "비용 절감 기회: #{best.supplier.name}에서 #{saving_pct}% 저렴",
          body: "대체 거래처 #{cheaper.count}곳 발견. 최저가: $#{'%.0f' % best.unit_price} (현재: $#{'%.0f' % current_price})",
          metadata: {
            current_price: current_price,
            best_price: best.unit_price.to_f,
            saving_amount: saving.round(2),
            saving_pct: saving_pct,
            alternative_supplier: best.supplier.name,
            alternatives_count: cheaper.count
          },
          expires_at: 14.days.from_now
        }
      )
    end
  end
end
