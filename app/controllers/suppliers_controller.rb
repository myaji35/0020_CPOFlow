class SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: %i[show edit update]

  def index
    @suppliers = Supplier.by_name
    @suppliers = @suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    @suppliers = @suppliers.where(country: params[:country]) if params[:country].present?
    @suppliers = @suppliers.where(industry: params[:industry]) if params[:industry].present?
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

  private

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
