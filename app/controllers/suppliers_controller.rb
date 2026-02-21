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
    @contact_persons = @supplier.contact_persons.primary_first
    @supplier_products = @supplier.supplier_products.includes(:product)
    @orders = @supplier.orders.by_due_date.limit(20)
  end

  def new
    @supplier = Supplier.new
  end

  def create
    @supplier = Supplier.new(supplier_params)
    if @supplier.save
      redirect_to @supplier, notice: "거래처가 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @supplier.update(supplier_params)
      redirect_to @supplier, notice: "거래처 정보가 수정되었습니다."
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
