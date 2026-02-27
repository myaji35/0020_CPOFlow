class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]
  before_action :require_manager!, only: %i[destroy]

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

    sort = params[:sort] || "due_date"
    orders_scope = case sort
    when "value"   then orders_scope.order(estimated_value: :desc)
    when "recent"  then orders_scope.order(created_at: :desc)
    else                orders_scope.by_due_date
    end

    @orders           = orders_scope.includes(:project, :supplier)
    @order_status_counts = @client.orders.group(:status).count
    @delivered_count  = @client.orders.where(status: :delivered).count
    total             = @client.orders.where.not(due_date: nil).count
    overdue           = @client.orders.where("due_date < ? AND status != ?", Date.today, Order.statuses[:delivered]).count
    @on_time_rate     = total > 0 ? ((total - overdue).to_f / total * 100).round(1) : nil
    @risk_grade       = calculate_client_risk(@client, @on_time_rate, overdue)

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

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(
      :name, :code, :country, :industry, :address, :website,
      :credit_grade, :contract_start_date, :payment_terms, :currency,
      :ecount_code, :notes, :active
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

  def require_manager!
    unless current_user.manager? || current_user.admin?
      redirect_to clients_path, alert: "권한이 없습니다."
    end
  end
end
