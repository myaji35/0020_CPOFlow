# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :require_admin_or_manager!

  def index
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    @from_str   = @date_range.first.strftime("%Y-%m-%d")
    @to_str     = @date_range.last.strftime("%Y-%m-%d")

    @boards        = KanbanBoard.ordered
    @selected_board = params[:board_id].present? ? KanbanBoard.find_by(id: params[:board_id]) : nil

    # ISS-222: drill-down 필터
    @available_branches = User.where.not(branch: [ nil, "" ]).distinct.pluck(:branch).sort
    @selected_branch    = params[:branch].presence_in(@available_branches)
    @available_users    = User.order(:name)
    @selected_assignee_id = params[:assignee_id].presence

    @kpi         = build_kpi(@date_range)
    @monthly     = build_monthly_trend
    @funnel      = build_funnel
    @by_client   = build_by_client(@date_range)
    @by_supplier = build_by_supplier(@date_range)
    @by_project  = build_by_project(@date_range)
    @by_assignee = build_by_assignee(@date_range)
    # ISS-222: by_branch 추가
    @by_branch   = build_by_branch(@date_range)
  end

  def export_pdf
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    @from_str   = @date_range.first.strftime("%Y-%m-%d")
    @to_str     = @date_range.last.strftime("%Y-%m-%d")

    @boards        = KanbanBoard.ordered
    @selected_board = params[:board_id].present? ? KanbanBoard.find_by(id: params[:board_id]) : nil

    @kpi         = build_kpi(@date_range)
    @monthly     = build_monthly_trend
    @funnel      = build_funnel
    @by_client   = build_by_client(@date_range)
    @by_supplier = build_by_supplier(@date_range)
    @by_project  = build_by_project(@date_range)
    @by_assignee = build_by_assignee(@date_range)

    render layout: false
  end

  def export_csv
    @period     = params[:period] || "this_month"
    @date_range = parse_period(@period, params[:from], params[:to])
    @selected_board = params[:board_id].present? ? KanbanBoard.find_by(id: params[:board_id]) : nil
    orders      = report_scoped_orders.includes(:client, :supplier, :project, :user)
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

  # ── 보드 스코핑 ────────────────────────────────────────────
  def report_scoped_orders
    base = scoped_orders
    base = base.where(kanban_board_id: @selected_board.id) if @selected_board
    # ISS-222: 지사(branch) drill-down — User를 통해 필터
    if @selected_branch.present?
      branch_user_ids = User.where(branch: @selected_branch).pluck(:id)
      base = base.where(user_id: branch_user_ids).or(base.joins(:assignees).where(users: { id: branch_user_ids }))
    end
    # ISS-222: 담당자(assignee) drill-down
    if @selected_assignee_id.present?
      base = base.joins(:assignees).where(users: { id: @selected_assignee_id })
    end
    base
  end

  # ── 기간 파싱 ──────────────────────────────────────────────
  def parse_period(period, from, to)
    today = Date.today
    case period
    when "last_month"   then 1.month.ago.to_date.beginning_of_month..1.month.ago.to_date.end_of_month
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
    # ISS-206: 전년 동기 (YoY) 범위 — 같은 기간을 1년 전 시점으로
    yoy  = order_stats(calc_yoy_range(range))

    {
      new_orders:     curr[:count],
      prev_orders:    prev[:count],
      yoy_orders:     yoy[:count],
      delivered:      curr[:delivered],
      prev_delivered: prev[:delivered],
      yoy_delivered:  yoy[:delivered],
      total_value:    curr[:value],
      prev_value:     prev[:value],
      yoy_value:      yoy[:value],
      on_time_rate:   curr[:on_time_rate],
      prev_on_time:   prev[:on_time_rate],
      yoy_on_time:    yoy[:on_time_rate],
      # ISS-267: done/get_grn/give_up 모두 제외 — 완료·포기·수령 건은 "지연/긴급" 집계 대상 아님
      overdue:        report_scoped_orders.where("due_date < ?", Date.today).where.not(status: [ :get_grn, :give_up, :done ]).count,
      urgent:         report_scoped_orders.joins(:card_status).where(card_statuses: { key: %w[urgent high overdue] }).where.not(status: [ :get_grn, :give_up, :done ]).count,
      avg_lead_days:  calc_avg_lead_days(range)
    }
  end

  def order_stats(range)
    base      = report_scoped_orders.where(created_at: range)
    # ISS-267: 납품 완료는 get_grn + done (9단계 칸반에서 done이 최종 종료)
    delivered = report_scoped_orders.where(status: [ :get_grn, :done ]).where(updated_at: range)
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

  # ISS-206: 전년 동기 (Year-over-Year)
  def calc_yoy_range(range)
    (range.first - 1.year)..(range.last - 1.year)
  end

  def calc_avg_lead_days(range)
    # ISS-267: get_grn + done 포함하여 평균 리드타임 산출
    delivered = report_scoped_orders.where(status: [ :get_grn, :done ]).where(updated_at: range)
    cnt = delivered.count
    return 0.0 if cnt == 0
    total_days = delivered.sum("JULIANDAY(orders.updated_at) - JULIANDAY(orders.created_at)")
    (total_days.to_f / cnt).round(1)
  end

  # ── 월별 트렌드 (최근 12개월 고정) ────────────────────────
  def build_monthly_trend
    (11.downto(0)).map do |i|
      m = i.months.ago.beginning_of_month
      r = m..(m.end_of_month)
      {
        label:     m.strftime("%y.%m"),
        orders:    report_scoped_orders.where(created_at: r).count,
        # ISS-267: 월별 trend의 delivered도 get_grn + done
        delivered: report_scoped_orders.where(status: [ :get_grn, :done ]).where(updated_at: r).count,
        value:     (report_scoped_orders.where(created_at: r).sum(:estimated_value).to_f / 1000).round
      }
    end
  end

  # ── 파이프라인 퍼널 ────────────────────────────────────────
  def build_funnel
    report_scoped_orders.group(:status).count
  end

  # ── Top 10 ─────────────────────────────────────────────────
  def build_by_client(range)
    report_scoped_orders.joins(:client).where(created_at: range)
         .group("clients.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  def build_by_supplier(range)
    report_scoped_orders.joins(:supplier).where(created_at: range)
         .group("suppliers.name").count
         .sort_by { |_, v| -v }.first(10)
  end

  def build_by_project(range)
    report_scoped_orders.joins(:project).where(created_at: range)
         .group("projects.name").sum(:estimated_value)
         .sort_by { |_, v| -(v || 0) }.first(10)
  end

  # ── 담당자별 성과 ──────────────────────────────────────────
  def build_by_assignee(range)
    scope = User.joins(:created_orders)
        .where(created_orders: { created_at: range })
    scope = scope.where(created_orders: { kanban_board_id: @selected_board.id }) if @selected_board
    # ISS-267: delivered = get_grn(6) + done(8)
    scope.group("users.id", "users.name")
        .select(
          "users.id, users.name,
           COUNT(created_orders.id) AS order_count,
           SUM(CASE WHEN created_orders.status IN (6, 8) THEN 1 ELSE 0 END) AS delivered_count,
           SUM(CASE WHEN created_orders.status IN (6, 8)
                     AND created_orders.due_date >= DATE(created_orders.updated_at)
                    THEN 1 ELSE 0 END) AS on_time_count"
        )
        .order("COUNT(created_orders.id) DESC")
        .to_a
  end

  # ISS-222: 지사별 실적
  def build_by_branch(range)
    scope = User.where.not(branch: [ nil, "" ])
                .joins(:created_orders)
                .where(created_orders: { created_at: range })
    scope = scope.where(created_orders: { kanban_board_id: @selected_board.id }) if @selected_board
    # ISS-267: delivered = get_grn(6) + done(8)
    scope.group("users.branch")
        .select(
          "users.branch,
           COUNT(created_orders.id) AS order_count,
           COALESCE(SUM(created_orders.estimated_value), 0) AS total_value,
           SUM(CASE WHEN created_orders.status IN (6, 8) THEN 1 ELSE 0 END) AS delivered_count,
           SUM(CASE WHEN created_orders.status IN (6, 8)
                     AND created_orders.due_date >= DATE(created_orders.updated_at)
                    THEN 1 ELSE 0 END) AS on_time_count"
        )
        .order("COUNT(created_orders.id) DESC")
        .to_a
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
