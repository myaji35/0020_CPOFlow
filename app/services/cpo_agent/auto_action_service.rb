# frozen_string_literal: true

module CpoAgent
  class AutoActionService
    def self.execute(order, insight, user)
      new(order, insight, user).execute
    end

    def initialize(order, insight, user)
      @order = order
      @insight = insight
      @user = user
    end

    def execute
      return unless @user
      return unless AgentTrustLevel.auto_mode?(user: @user, insight_type: @insight.insight_type)

      case @insight.insight_type
      when "price_comparison" then auto_price_comparison
      when "supplier_risk"   then auto_supplier_risk
      when "due_date_risk"   then auto_due_date_notification
      when "cost_saving"     then auto_cost_saving
      end
    rescue => e
      Rails.logger.warn "[CpoAgent::AutoAction] #{e.message}"
    end

    private

    def auto_price_comparison
      past = Order.where(supplier_id: @order.supplier_id)
                  .where.not(id: @order.id, estimated_value: [ nil, 0 ])
                  .order(created_at: :desc).limit(3)
      return if past.empty?

      body = "[CPO Agent] 과거 견적 비교\n"
      past.each { |o| body += "- #{o.title}: $#{o.estimated_value} (#{o.created_at.strftime('%Y-%m-%d')})\n" }
      body += "현재: $#{@order.estimated_value}"

      create_auto_comment(body)
      create_auto_insight("과거 견적 3건 비교를 자동 첨부했습니다", "comment_added")
    end

    def auto_supplier_risk
      alternatives = Supplier.active.where.not(id: @order.supplier_id)
                             .where(credit_grade: %w[A B]).limit(3)
      return if alternatives.empty?

      body = "[CPO Agent] 대체 거래처 추천\n"
      alternatives.each do |s|
        contact = s.primary_contact
        body += "- #{s.name} (#{s.credit_grade}등급)"
        body += " | #{contact.email}" if contact&.email
        body += "\n"
      end

      create_auto_comment(body)
      create_auto_insight("대체 거래처 #{alternatives.count}곳을 자동 추천했습니다", "alternatives_suggested")
    end

    def auto_due_date_notification
      assignees = @order.assignees.presence || []
      assignees.each do |assignee|
        user = assignee.respond_to?(:user) ? assignee.user : nil
        next unless user
        Notification.create!(
          user:              user,
          notifiable:        @order,
          notification_type: "due_date_risk",
          title:             "[CPO Agent] 납기 위험: #{@order.title}",
          body:              "납기일 #{@order.due_date&.strftime('%Y-%m-%d')} — 즉시 조치 필요"
        )
      end
      create_auto_insight("담당자에게 납기 위험 알림을 자동 발송했습니다", "notification_sent")
    end

    def auto_cost_saving
      metadata = @insight.metadata
      return unless metadata["best_price"] && metadata["alternative_supplier"]

      supplier = Supplier.find_by(name: metadata["alternative_supplier"])
      return unless supplier

      existing = @order.order_quotes.find_by(supplier: supplier)
      return if existing

      @order.order_quotes.create!(
        supplier: supplier,
        unit_price: metadata["best_price"],
        currency: @order.currency || "AED",
        notes: "[CPO Agent] 자동 추가 — 비용 절감 #{metadata['saving_pct']}%"
      )
      create_auto_insight("#{supplier.name} 견적을 자동 추가했습니다 (-#{metadata['saving_pct']}%)", "quote_added")
    end

    def create_auto_comment(body)
      @order.comments.create!(user: @user, body: body)
    end

    def create_auto_insight(title, action_type)
      AgentInsight.create!(
        order: @order,
        insight_type: @insight.insight_type,
        severity: :info,
        title: "[자동 처리] #{title}",
        body: "CPO Agent가 신뢰 레벨 기반으로 자동 실행했습니다",
        metadata: { auto_action: true, action_type: action_type },
        expires_at: 3.days.from_now
      )
    end
  end
end
