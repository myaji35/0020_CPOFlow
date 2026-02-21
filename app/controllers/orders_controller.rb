class OrdersController < ApplicationController
  before_action :set_order, only: %i[show edit update destroy move_status]

  def index
    @orders = Order.all.includes(:assignees, :tasks, :user).by_due_date
    @orders = @orders.where(status: params[:status]) if params[:status].present?
    @orders = @orders.where("title LIKE ? OR customer_name LIKE ?",
                            "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
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
      redirect_to kanban_path, notice: "Order created and added to Inbox."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @order.update(order_params)
      Activity.create!(order: @order, user: current_user, action: "updated")
      redirect_to @order, notice: "Order updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    redirect_to kanban_path, notice: "Order removed."
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
      redirect_back fallback_location: kanban_path, notice: "Status updated to #{Order::STATUS_LABELS[new_status]}."
    else
      redirect_back fallback_location: kanban_path, alert: "Failed to update status."
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
