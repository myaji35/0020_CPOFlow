class KanbanController < ApplicationController
  def index
    @columns = Order::KANBAN_COLUMNS.map do |status|
      orders = Order.where(status: status)
                    .by_due_date
                    .includes(:assignees, :tasks, :user)
      [ status, orders ]
    end.to_h
  end

  def move
    @order = Order.find(params[:id])
    old_status = @order.status

    if @order.update(status: params[:status])
      Activity.create!(
        order: @order,
        user: current_user,
        action: "status_changed",
        from_status: Order.statuses[old_status],
        to_status: Order.statuses[@order.status]
      )
      render json: { success: true, new_status: @order.status }
    else
      render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
