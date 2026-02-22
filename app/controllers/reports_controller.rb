# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_admin_or_manager!

  def index
    # 월별 수주 트렌드 (최근 12개월)
    @monthly_orders = Order.group_by_month(:created_at, last: 12, format: "%Y-%m")
                           .count
    @monthly_delivered = Order.delivered
                              .group_by_month(:updated_at, last: 12, format: "%Y-%m")
                              .count
    @monthly_value = Order.group_by_month(:created_at, last: 12, format: "%Y-%m")
                          .sum(:estimated_value)

    # 발주처별 수주 금액 Top 10
    @by_client = Order.joins(:client)
                      .group("clients.name")
                      .sum(:estimated_value)
                      .sort_by { |_, v| -(v || 0) }
                      .first(10)

    # 거래처별 발주 건수 Top 10
    @by_supplier = Order.joins(:supplier)
                        .group("suppliers.name")
                        .count
                        .sort_by { |_, v| -v }
                        .first(10)

    # 현장별 수주액 Top 10
    @by_project_type = Project.joins(:orders)
                               .group("projects.name")
                               .sum("orders.estimated_value")
                               .sort_by { |_, v| -(v || 0) }
                               .first(10)

    # 상태별 주문 현황
    @by_status = Order::STATUS_LABELS.map do |k, v|
      { status: v, count: Order.where(status: k).count }
    end

    # 이번달 KPI
    month_start = Date.today.beginning_of_month
    delivered_this_month = Order.delivered.where(updated_at: month_start..)
    on_time_count = delivered_this_month.where("orders.due_date >= DATE(orders.updated_at)").count

    @kpi = {
      new_orders:   Order.where(created_at: month_start..).count,
      delivered:    delivered_this_month.count,
      total_value:  Order.where(created_at: month_start..).sum(:estimated_value).to_f,
      on_time_rate: delivered_this_month.any? ? (on_time_count.to_f / delivered_this_month.count * 100).round(1) : 0.0,
      overdue:      Order.where("due_date < ?", Date.today).where.not(status: :delivered).count,
      urgent:       Order.where(priority: :urgent).where.not(status: :delivered).count
    }

    # 위험도별 분포
    @by_risk = {
      "critical" => Order.where(risk_level: "critical").where.not(status: :delivered).count,
      "high"     => Order.where(risk_level: "high").where.not(status: :delivered).count,
      "medium"   => Order.where(risk_level: "medium").where.not(status: :delivered).count,
      "low"      => Order.where(risk_level: "low").where.not(status: :delivered).count
    }
  end

  private

  def require_admin_or_manager!
    unless current_user&.admin? || current_user&.manager?
      redirect_to root_path, alert: "접근 권한이 없습니다."
    end
  end
end
