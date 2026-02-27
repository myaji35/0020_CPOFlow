# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_admin_or_manager!

  def index
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    @from_str   = @date_range.first.strftime("%Y-%m-%d")
    @to_str     = @date_range.last.strftime("%Y-%m-%d")

    @kpi         = build_kpi(@date_range)
    @monthly     = build_monthly_trend
    @funnel      = build_funnel
    @by_client   = build_by_client(@date_range)
    @by_supplier = build_by_supplier(@date_range)
    @by_project  = build_by_project(@date_range)
    @by_assignee = build_by_assignee(@date_range)
  end

  def export_csv
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    orders      = Order.includes(:client, :supplier, :project, :user)
                       .where(created_at: @date_range)
                       .order(created_at: :desc)

    respond_to do |format|
      format.csv do
        send_data generate_csv(orders),
                  filename: "orders_#{Date.today}.csv",
                  type: "text/csv; charset=utf-8",
                  disposition: "attachment"
      end
    end
  end

  private

  # ── 기간 파싱 ──────────────────────────────────────────────
  def parse_period(period, from, to)
    today = Date.today
    case period
    when "last_month"   then 1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when "this_quarter" then today.beginning_of_quarter..today.end_of_quarter
    when "this_year"    then today.beginning_of_year..today.end_of_year
    when "custom"
      f = (Date.parse(from.to_s) rescue today.beginning_of_month)
      t = (Date.parse(to.to_s)   rescue today)
      f..t
    else # this_month (default)
      today.beginning_of_month..today.end_of_month
    end
  end

  # ── KPI ────────────────────────────────────────────────────
  def build_kpi(range)
    curr = order_stats(range)
    prev = order_stats(calc_prev_range(range))

    {
      new_orders:     curr[:count],
      prev_orders:    prev[:count],
      delivered:      curr[:delivered],
      prev_delivered: prev[:delivered],
      total_value:    curr[:value],
      prev_value:     prev[:value],
      on_time_rate:   curr[:on_time_rate],
      prev_on_time:   prev[:on_time_rate],
      overdue:        Order.where("due_date < ?", Date.today).where.not(status: :delivered).count,
      urgent:         Order.where(priority: :urgent).where.not(status: :delivered).count,
      avg_lead_days:  calc_avg_lead_days(range)
    }
  end

  def order_stats(range)
    base      = Order.where(created_at: range)
    delivered = Order.delivered.where(updated_at: range)
    on_time   = delivered.where("orders.due_date >= DATE(orders.updated_at)").count
    {
      count:        base.count,
      delivered:    delivered.count,
      value:        base.sum(:estimated_value).to_f,
      on_time_rate: delivered.any? ? (on_time.to_f / delivered.count * 100).round(1) : 0.0
    }
  end

  def calc_prev_range(range)
    duration = (range.last - range.first).to_i
    (range.first - duration - 1)..(range.first - 1)
  end

  def calc_avg_lead_days(range)
    delivered = Order.delivered.where(updated_at: range)
    return 0.0 if delivered.empty?
    total = delivered.sum { |o| (o.updated_at.to_date - o.created_at.to_date).to_i }
    (total.to_f / delivered.count).round(1)
  end

  # ── 월별 트렌드 (최근 12개월 고정) ────────────────────────
  def build_monthly_trend
    (11.downto(0)).map do |i|
      m = i.months.ago.beginning_of_month
      r = m..(m.end_of_month)
      {
        label:     m.strftime("%y.%m"),
        orders:    Order.where(created_at: r).count,
        delivered: Order.delivered.where(updated_at: r).count,
        value:     (Order.where(created_at: r).sum(:estimated_value).to_f / 1000).round
      }
    end
  end

  # ── 파이프라인 퍼널 ────────────────────────────────────────
  def build_funnel
    Order.group(:status).count
  end

  # ── Top 10 ─────────────────────────────────────────────────
  def build_by_client(range)
    Order.joins(:client).where(created_at: range)
         .group("clients.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  def build_by_supplier(range)
    Order.joins(:supplier).where(created_at: range)
         .group("suppliers.name").count
         .sort_by { |_, v| -v }.first(10)
  end

  def build_by_project(range)
    Order.joins(:project).where(created_at: range)
         .group("projects.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  # ── 담당자별 성과 ──────────────────────────────────────────
  def build_by_assignee(range)
    User.joins(:orders)
        .where(orders: { created_at: range })
        .group("users.id", "users.name")
        .select(
          "users.id, users.name,
           COUNT(orders.id) AS order_count,
           SUM(CASE WHEN orders.status = 6 THEN 1 ELSE 0 END) AS delivered_count,
           SUM(CASE WHEN orders.status = 6
                     AND orders.due_date >= DATE(orders.updated_at)
                    THEN 1 ELSE 0 END) AS on_time_count"
        )
        .order("order_count DESC")
  end

  # ── CSV 생성 ───────────────────────────────────────────────
  def generate_csv(orders)
    require "csv"
    CSV.generate(encoding: "UTF-8", col_sep: ",") do |csv|
      csv << %w[주문ID 제목 발주처 거래처 프로젝트 수주액 상태 납기일 담당자 생성일]
      orders.each do |o|
        csv << [
          o.id,
          o.title,
          o.client&.name,
          o.supplier&.name,
          o.project&.name,
          o.estimated_value,
          o.status,
          o.due_date&.strftime("%Y-%m-%d"),
          o.user&.name,
          o.created_at.strftime("%Y-%m-%d")
        ]
      end
    end
  end

  def require_admin_or_manager!
    redirect_to root_path, alert: "접근 권한이 없습니다." unless current_user&.admin? || current_user&.manager?
  end
end
