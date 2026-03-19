# frozen_string_literal: true

module CpoAgent
  class DueDateRiskAnalyzer
    def initialize(order)
      @order = order
    end

    def call
      return nil if @order.due_date.nil?
      return nil if @order.get_grn? || @order.give_up?

      days_left = (@order.due_date - Date.today).to_i
      return nil if days_left > 7

      risk = RiskAssessmentService.calculate(@order)

      severity = case days_left
                 when ..-1 then :alert
                 when 0..3 then :alert
                 else :warning
                 end

      overdue_label = days_left < 0 ? "#{days_left.abs}일 지연" : "D-#{days_left}"

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :due_date_risk,
        attrs: {
          severity: severity,
          title: "납기 #{overdue_label} — 위험도 #{risk[:level]}",
          body: "납기일: #{@order.due_date.strftime('%Y-%m-%d')} / 현재 상태: #{Order::STATUS_LABELS[@order.status]}",
          metadata: {
            days_left: days_left,
            risk_score: risk[:score],
            risk_level: risk[:level],
            current_status: @order.status
          },
          expires_at: 1.day.from_now
        }
      )
    end
  end
end
