class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]
  # ISS-264: viewer read-only — CRUD는 member 이상만
  before_action :require_member!, only: %i[new create edit update]
  before_action :require_manager!, only: %i[destroy]
  # ISS-380: MenuPermission DB 2차 가드 — require_*은 1차(role), enforce_*는 2차(DB 토글)
  before_action -> { enforce_menu_permission!(:clients, :create) }, only: %i[new create]
  before_action -> { enforce_menu_permission!(:clients, :update) }, only: %i[edit update]
  before_action -> { enforce_menu_permission!(:clients, :delete) }, only: %i[destroy]

  def index
    @clients = Client.active.by_name
    @clients = @clients.where("name LIKE ? OR code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    @clients = @clients.where(country: params[:country]) if params[:country].present?
    @clients = @clients.where(industry: params[:industry]) if params[:industry].present?

    # 정렬
    all = @clients.to_a
    all = case params[:sort]
    when "value"  then all.sort_by { |c| -c.total_order_value }
    when "orders" then all.sort_by { |c| -c.orders.count }
    else all
    end

    @total_value = all.sum(&:total_order_value)

    # KPI 카드
    @active_clients_count = all.count { |c| c.orders.exists? }
    @order_linked_count   = all.count { |c| c.orders.count > 0 }
    @recent_30d_count     = Client.active.where("created_at >= ?", 30.days.ago).count

    # 수동 페이지네이션
    @per_page    = 20
    @page        = (params[:page] || 1).to_i
    @total_count = all.size
    @total_pages = [ (@total_count.to_f / @per_page).ceil, 1 ].max
    @page        = [ [ @page, 1 ].max, @total_pages ].min
    @clients     = all.slice((@page - 1) * @per_page, @per_page) || []
  end

  def show
    @contact_persons = @client.contact_persons.primary_first
    @projects        = @client.projects.order(created_at: :desc)

    # FR-02: 거래이력 탭 강화
    orders_scope = @client.orders
    case params[:period]
    when "this_month" then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_month..)
    when "3months"    then orders_scope = orders_scope.where(created_at: 3.months.ago..)
    when "this_year"  then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_year..)
    end
    orders_scope = orders_scope.where(project_id: params[:project_id]) if params[:project_id].present?
    orders_scope = orders_scope.where(status: params[:order_status]) if params[:order_status].present?

    sort = params[:sort] || "due_date"
    orders_scope = case sort
    when "value"   then orders_scope.order(estimated_value: :desc)
    when "recent"  then orders_scope.order(created_at: :desc)
    else                orders_scope.by_due_date
    end

    @orders = orders_scope.includes(:project, :supplier)

    respond_to do |format|
      format.html
      format.csv do
        send_data client_orders_to_csv(@orders),
                  filename: "#{@client.name}-orders-#{Date.today}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end

    @order_status_counts = @client.orders.group(:status).count
    @delivered_count  = @client.orders.where(status: :get_grn).count
    total             = @client.orders.where.not(due_date: nil).count
    overdue           = @client.orders.where("due_date < ? AND status NOT IN (?, ?)", Date.today, Order.statuses[:get_grn], Order.statuses[:give_up]).count
    @on_time_rate     = total > 0 ? ((total - overdue).to_f / total * 100).round(1) : nil
    @risk_grade       = calculate_client_risk(@client, @on_time_rate, overdue)

    # ISS-215: Customer Intelligence — 추가 거래 품질 지표
    @customer_intel = build_customer_intel(@client)

    # FR-03: 월별 거래 추이 (최근 12개월)
    @monthly_trend = (11.downto(0)).map do |i|
      m = i.months.ago.to_date.beginning_of_month
      r = m..m.end_of_month
      {
        label:  m.strftime("%y.%m"),
        orders: @client.orders.where(created_at: r).count,
        value:  (@client.orders.where(created_at: r).sum(:estimated_value).to_f / 1000).round
      }
    end
  end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      redirect_to @client, notice: t("clients.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: t("clients.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @client.destroy
    redirect_to clients_path, notice: t("clients.delete_success")
  end

  # GET /clients/search?q=... (AJAX 자동완성용)
  def search
    q = params[:q].to_s.strip
    clients = Client.active.by_name
    clients = clients.where("name LIKE ? OR code LIKE ?", "%#{q}%", "%#{q}%") if q.present?
    results = clients.limit(10).map { |c| { id: c.id, name: c.name, code: c.code, country: c.country } }
    render json: results
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(
      :name, :code, :country, :industry, :address, :website,
      :credit_grade, :contract_start_date, :payment_terms, :currency,
      :ecount_code, :notes, :active, :default_assignee_id
    )
  end

  def calculate_client_risk(client, on_time_rate, overdue)
    return "N/A" if on_time_rate.nil?
    if on_time_rate >= 90 && overdue == 0 then "A"
    elsif on_time_rate >= 75 || overdue <= 1 then "B"
    elsif on_time_rate >= 60 || overdue <= 3 then "C"
    else "D"
    end
  end

  # ISS-215: 발주처 거래 품질 프로파일
  def build_customer_intel(client)
    all_orders = client.orders
    delivered  = all_orders.where(status: :get_grn)

    # 평균 리드타임 (생성 → 최종 납품)
    lead_days_arr = delivered.map { |o| (o.updated_at.to_date - o.created_at.to_date).to_i }
    avg_lead_days = lead_days_arr.any? ? (lead_days_arr.sum.to_f / lead_days_arr.size).round(1) : nil

    # 견적 갯수 평균 (까다로움 지수) — Order의 order_quotes 평균
    quote_counts = all_orders.joins("LEFT JOIN order_quotes ON order_quotes.order_id = orders.id")
                             .group("orders.id").count("order_quotes.id").values
    avg_quotes = quote_counts.any? ? (quote_counts.sum.to_f / quote_counts.size).round(1) : 0.0

    # 취소/포기(give_up) 비율
    give_up_count = all_orders.where(status: :give_up).count
    cancellation_rate = all_orders.count > 0 ? (give_up_count.to_f / all_orders.count * 100).round(1) : 0.0

    # 최근 30일 연체 트렌드 (30일 전 vs 현재)
    recent_overdue = all_orders.where("due_date < ? AND due_date >= ? AND status NOT IN (?, ?)",
                                       Date.today, 30.days.ago, Order.statuses[:get_grn], Order.statuses[:give_up]).count
    prev_overdue = all_orders.where("due_date < ? AND due_date >= ? AND status NOT IN (?, ?)",
                                     30.days.ago, 60.days.ago, Order.statuses[:get_grn], Order.statuses[:give_up]).count
    trend = if prev_overdue == 0
              recent_overdue > 0 ? :increasing : :stable
    else
              change = ((recent_overdue - prev_overdue).to_f / prev_overdue * 100)
              change > 20 ? :increasing : (change < -20 ? :decreasing : :stable)
    end

    # 평균 발주 금액
    avg_value = all_orders.average(:estimated_value).to_f.round(0)

    {
      avg_lead_days:     avg_lead_days,
      avg_quotes:        avg_quotes,
      give_up_count:     give_up_count,
      cancellation_rate: cancellation_rate,
      recent_overdue:    recent_overdue,
      prev_overdue:      prev_overdue,
      trend:             trend,
      avg_value:         avg_value,
      total_orders:      all_orders.count,
      delivered_count:   delivered.count,
      computed_at:       Time.current
    }
  end

  def client_orders_to_csv(orders)
    require "csv"
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << [ "주문번호", "제목", "상태", "납기일", "금액", "거래처", "현장", "담당자" ]
      orders.each do |o|
        csv << [
          o.id,
          o.title,
          Order::STATUS_LABELS[o.status] || o.status,
          o.due_date&.strftime("%Y-%m-%d"),
          o.estimated_value,
          o.supplier&.name,
          o.project&.name,
          o.assignees.map(&:display_name).join("|")
        ]
      end
    end
  end

  def require_manager!
    unless current_user.manager? || current_user.admin?
      redirect_to clients_path, alert: "권한이 없습니다."
    end
  end
end
