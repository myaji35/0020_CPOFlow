class SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: %i[show edit update]

  def index
    @suppliers = Supplier.by_name
    @suppliers = @suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    @suppliers = @suppliers.where(country: params[:country]) if params[:country].present?
    @suppliers = @suppliers.where(industry: params[:industry]) if params[:industry].present?

    # 통계 카드
    all_suppliers       = Supplier.all.to_a
    @total_count        = all_suppliers.size
    @total_supply_value = all_suppliers.sum(&:total_supply_value)
    @active_count       = Supplier.active.count

    # 수동 페이지네이션
    @per_page    = 20
    @page        = (params[:page] || 1).to_i
    @filtered_count = @suppliers.count
    @total_pages = [ (@filtered_count.to_f / @per_page).ceil, 1 ].max
    @page        = [ [ @page, 1 ].max, @total_pages ].min
    @suppliers   = @suppliers.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    @contact_persons   = @supplier.contact_persons.primary_first
    @supplier_products = @supplier.supplier_products.includes(:product)

    # FR-03: 납품 이력 탭 강화
    orders_scope = @supplier.orders
    case params[:period]
    when "this_month" then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_month..)
    when "3months"    then orders_scope = orders_scope.where(created_at: 3.months.ago..)
    when "this_year"  then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_year..)
    end

    sort = params[:sort] || "due_date"
    orders_scope = case sort
    when "value"  then orders_scope.order(estimated_value: :desc)
    when "recent" then orders_scope.order(created_at: :desc)
    else               orders_scope.by_due_date
    end

    @orders              = orders_scope.includes(:client, :project)
    @order_status_counts = @supplier.orders.group(:status).count
    total                = @supplier.orders.where.not(due_date: nil).count
    overdue              = @supplier.orders.where("due_date < ? AND status != ?", Date.today, Order.statuses[:delivered]).count
    @on_time_rate        = total > 0 ? ((total - overdue).to_f / total * 100).round(1) : nil
    @performance_grade   = calculate_supplier_performance(@on_time_rate, total)

    # FR-05: 월별 납품 추이 (최근 12개월)
    @monthly_supply = (11.downto(0)).map do |i|
      m = i.months.ago.to_date.beginning_of_month
      r = m..m.end_of_month
      delivered = @supplier.orders.where(status: :delivered).where(updated_at: r)
      {
        label:     m.strftime("%y.%m"),
        orders:    @supplier.orders.where(created_at: r).count,
        delivered: delivered.count,
        value:     (delivered.sum(:estimated_value).to_f / 1000).round
      }
    end
  end

  def new
    @supplier = Supplier.new
  end

  def create
    @supplier = Supplier.new(supplier_params)
    if @supplier.save
      redirect_to @supplier, notice: t("suppliers.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @supplier.update(supplier_params)
      redirect_to @supplier, notice: t("suppliers.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # GET /suppliers/search?q=... (AJAX 자동완성용)
  def search
    q = params[:q].to_s.strip
    suppliers = Supplier.by_name
    suppliers = suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{q}%", "%#{q}%") if q.present?
    results = suppliers.limit(10).map { |s| { id: s.id, name: s.name, code: s.ecount_code, industry: s.industry_label } }
    render json: results
  end

  private

  def calculate_supplier_performance(on_time_rate, total_orders)
    return "N/A" if on_time_rate.nil? || total_orders < 3
    if on_time_rate >= 95 then "A"
    elsif on_time_rate >= 85 then "B"
    elsif on_time_rate >= 70 then "C"
    else "D"
    end
  end

  def set_supplier
    @supplier = Supplier.find(params[:id])
  end

  def supplier_params
    params.require(:supplier).permit(
      :name, :code, :country, :email, :phone, :notes, :active, :ecount_code,
      :address, :website, :credit_grade, :payment_terms, :lead_time_days,
      :currency, :industry
    )
  end
end
