class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]
  before_action :require_manager!, only: %i[destroy]

  def index
    @clients = Client.active.by_name
    @clients = @clients.where("name LIKE ? OR code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    @clients = @clients.where(country: params[:country]) if params[:country].present?
    @clients = @clients.where(industry: params[:industry]) if params[:industry].present?
    @total_value = @clients.sum { |c| c.total_order_value }
  end

  def show
    @contact_persons = @client.contact_persons.primary_first
    @projects        = @client.projects.order(created_at: :desc)
    @orders          = @client.orders.by_due_date.limit(20)
  end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      redirect_to @client, notice: "발주처가 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: "발주처 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @client.destroy
    redirect_to clients_path, notice: "발주처가 삭제되었습니다."
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

  def require_manager!
    unless current_user.manager? || current_user.admin?
      redirect_to clients_path, alert: "권한이 없습니다."
    end
  end
end
