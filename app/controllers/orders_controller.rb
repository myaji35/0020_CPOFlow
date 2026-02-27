class OrdersController < ApplicationController
  before_action :set_order, only: %i[show edit update destroy move_status quick_update]

  def index
    @orders = Order.all.includes(:assignees, :tasks, :user, :client, :project, :supplier).by_due_date

    # 기존 필터
    @orders = @orders.where(status: params[:status]) if params[:status].present?
    @orders = @orders.where("orders.title LIKE ? OR orders.customer_name LIKE ?",
                            "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?

    # 거래내역 추적 필터 (FR-01)
    @orders = @orders.where(client_id: params[:client_id])     if params[:client_id].present?
    @orders = @orders.where(supplier_id: params[:supplier_id]) if params[:supplier_id].present?
    @orders = @orders.where(project_id: params[:project_id])   if params[:project_id].present?
    @orders = @orders.joins(:assignments).where(assignments: { user_id: params[:user_id] }) if params[:user_id].present?

    # 납기일 범위 필터
    @orders = @orders.where(due_date: params[:due_from]..) if params[:due_from].present?
    @orders = @orders.where(due_date: ..params[:due_to])   if params[:due_to].present?

    # 기간 필터
    case params[:period]
    when "this_month"
      @orders = @orders.where(created_at: Time.current.beginning_of_month..)
    when "3months"
      @orders = @orders.where(created_at: 3.months.ago..)
    when "this_year"
      @orders = @orders.where(created_at: Time.current.beginning_of_year..)
    when "custom"
      @orders = @orders.where(created_at: params[:date_from]..) if params[:date_from].present?
      @orders = @orders.where(created_at: ..Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
    end

    # 필터 드롭다운용 데이터
    @filter_clients   = Client.active.by_name
    @filter_suppliers = Supplier.active.by_name
    @filter_projects  = Project.active.by_name
    @filter_users     = User.order(:name)

    @total_count = @orders.count
    @orders = @orders.limit(50).offset((params[:page].to_i > 0 ? params[:page].to_i - 1 : 0) * 50)
    @current_page = [ params[:page].to_i, 1 ].max
    @total_pages = (@total_count / 50.0).ceil
  end

  def show
    @tasks    = @order.tasks.by_due.includes(:assignee)
    @comments = @order.comments.chronological.includes(:user)
    @activities = @order.activities.recent.includes(:user).limit(20)
    @team_members = User.all.order(:name)
  end

  def new
    @order = Order.new
    @order.due_date = 30.days.from_now
  end

  def create
    @order = Order.new(order_params)
    @order.user = current_user
    @order.status = :inbox

    if @order.save
      Activity.create!(order: @order, user: current_user, action: "created")
      redirect_to kanban_path, notice: t("orders.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @order.update(order_params)
      Activity.create!(order: @order, user: current_user, action: "updated")
      redirect_to @order, notice: t("orders.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    redirect_to kanban_path, notice: t("orders.delete_success")
  end

  def move_status
    old_status = @order.status
    new_status = params[:status]

    if @order.update(status: new_status)
      Activity.create!(
        order: @order,
        user: current_user,
        action: "status_changed",
        from_status: Order.statuses[old_status],
        to_status: Order.statuses[@order.status]
      )
      redirect_back fallback_location: kanban_path, notice: t("orders.status_updated", status: t("orders.status.#{new_status}", default: new_status))
    else
      redirect_back fallback_location: kanban_path, alert: "Failed to update status."
    end
  end

  def quick_update
    permitted = params.require(:order).permit(:due_date, :status)
    if @order.update(permitted)
      Activity.create!(order: @order, user: current_user, action: "updated")
      render json: { success: true }
    else
      render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end

  def order_params
    params.require(:order).permit(
      :title, :customer_name, :description, :status, :priority,
      :due_date, :item_name, :quantity, :currency, :estimated_value,
      :tags, :source_email_id, :original_email_subject,
      :original_email_body, :original_email_from,
      :client_id, :supplier_id, :project_id
    )
  end
end
