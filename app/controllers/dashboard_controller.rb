class DashboardController < ApplicationController
  def index
    # ── 현재 상황 (KPI Cards) ─────────────────────────────────
    @total_active   = Order.active.count
    @overdue_count  = Order.overdue.count
    @urgent_count   = Order.urgent.count
    @delivered_this_month = Order.delivered
                                 .where(updated_at: Time.current.beginning_of_month..)
                                 .count

    @urgent_orders  = Order.urgent.by_due_date.limit(5).includes(:assignees)
    @recent_orders  = Order.order(created_at: :desc).limit(8).includes(:assignees, :tasks)
    @kanban_counts  = Order.group(:status).count

    # ── 기간별 분석 데이터 ────────────────────────────────────
    @weekly_data    = build_weekly_data(8)
    @monthly_data   = build_monthly_data(12)
    @quarterly_data = build_quarterly_data(6)
    @yearly_data    = build_yearly_data(3)

    # ── 스마트 KPI 추가 ───────────────────────────────────────
    @total_value_this_month = Order.where(created_at: Time.current.beginning_of_month..).sum(:estimated_value).to_f
    @total_value_last_month = Order.where(created_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month).sum(:estimated_value).to_f
    @on_time_rate_this_month = calculate_on_time_rate(Time.current.beginning_of_month, Time.current.end_of_month)
    @on_time_rate_last_month = calculate_on_time_rate(1.month.ago.beginning_of_month, 1.month.ago.end_of_month)

    # 현장 카테고리별 수주 (현황)
    @site_category_data = build_site_category_data

    # FR-06: 발주처 Top5 / 거래처 Top5
    @top_clients = Client.joins(:orders)
                         .select("clients.id, clients.name, COUNT(orders.id) AS order_count, SUM(orders.estimated_value) AS total_value")
                         .group("clients.id, clients.name")
                         .order(Arel.sql("total_value DESC NULLS LAST"))
                         .limit(5)
    @top_suppliers = Supplier.joins(:orders)
                             .select("suppliers.id, suppliers.name, COUNT(orders.id) AS order_count, SUM(orders.estimated_value) AS total_value")
                             .group("suppliers.id, suppliers.name")
                             .order(Arel.sql("total_value DESC NULLS LAST"))
                             .limit(5)

    # 비자 만료 임박 (90일 이내)
    @expiring_visas = Visa.where(status: "active")
                          .where(expiry_date: Date.today..90.days.from_now)
                          .order(:expiry_date)
                          .includes(:employee)
                          .limit(5)

    # Google Sheets 동기화 상태
    @last_sync   = SheetsSyncLog.recent.first
    @sheets_mock = Sheets::SheetsService.new.mock_mode?
  end

  def sync_sheets
    SheetsSyncJob.perform_later
    redirect_to dashboard_path, notice: t("dashboard.sync_started")
  end

  private

  def calculate_on_time_rate(start_time, end_time)
    delivered = Order.delivered.where(updated_at: start_time..end_time)
    return 0 if delivered.count == 0
    on_time = delivered.where("due_date >= date(updated_at)")
    (on_time.count.to_f / delivered.count * 100).round(1)
  end

  def build_site_category_data
    %w[nuclear hydro tunnel gtx].map do |cat|
      projects = Project.where(site_category: cat)
      order_ids = Order.where(project_id: projects.pluck(:id))
      {
        category: cat,
        label: { "nuclear" => "원전", "hydro" => "수력", "tunnel" => "터널", "gtx" => "GTX" }[cat],
        orders: order_ids.count,
        delivered: order_ids.where(status: "delivered").count,
        value: order_ids.sum(:estimated_value).to_f
      }
    end
  end

  # 주간 데이터 (최근 N주, 월요일 기준)
  def build_weekly_data(weeks)
    (0...weeks).map do |i|
      week_start = (Date.today - i.weeks).beginning_of_week
      week_end   = week_start.end_of_week
      orders     = Order.where(created_at: week_start..week_end)
      {
        label:     "W#{week_start.cweek}",
        orders:    orders.count,
        delivered: orders.where(status: "delivered").count
      }
    end.reverse
  end

  # 월간 데이터 (최근 N개월)
  def build_monthly_data(months)
    (0...months).map do |i|
      month_date = Date.today - i.months
      period     = month_date.beginning_of_month..month_date.end_of_month
      orders     = Order.where(created_at: period)
      {
        label:     month_date.strftime("%m월"),
        orders:    orders.count,
        delivered: orders.where(status: "delivered").count
      }
    end.reverse
  end

  # 분기 데이터 (최근 N분기)
  def build_quarterly_data(quarters)
    (0...quarters).map do |i|
      # 현재 분기에서 i분기 전
      base       = Date.today << (i * 3)
      q_start    = base.beginning_of_quarter
      q_end      = base.end_of_quarter
      orders     = Order.where(created_at: q_start..q_end)
      delivered  = orders.where(status: "delivered")
      on_time    = delivered.where("due_date >= date(updated_at)")
      rate       = delivered.count > 0 ? (on_time.count.to_f / delivered.count * 100).round(1) : 0
      {
        label:        "#{q_start.year} Q#{(q_start.month / 3.0).ceil}",
        orders:       orders.count,
        delivered:    delivered.count,
        on_time_rate: rate
      }
    end.reverse
  end

  # 연간 데이터 (최근 N년)
  def build_yearly_data(years)
    (0...years).map do |i|
      year      = Date.today.year - i
      period    = Date.new(year, 1, 1)..Date.new(year, 12, 31)
      orders    = Order.where(created_at: period)
      delivered = orders.where(status: "delivered")
      on_time   = delivered.where("due_date >= date(updated_at)")
      rate      = delivered.count > 0 ? (on_time.count.to_f / delivered.count * 100).round(1) : 0
      {
        label:        year.to_s,
        orders:       orders.count,
        delivered:    delivered.count,
        on_time_rate: rate,
        total_value:  orders.sum(:estimated_value).to_f
      }
    end.reverse
  end
end
