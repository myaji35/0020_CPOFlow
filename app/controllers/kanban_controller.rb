class KanbanController < ApplicationController
  def index
    @columns = Order::KANBAN_COLUMNS.map do |status|
      orders = Order.where(status: status)
                    .by_due_date
                    .includes(:assignees, :tasks, :user)
      [ status, orders ]
    end.to_h
    @filter_employees = Employee.active.by_name

    # Inbox 전용: reference_no 기준 그룹핑 (대표 카드 1개 + 스레드 수)
    @inbox_grouped = build_inbox_groups(@columns["inbox"] || [])
  end

  private

  # Inbox 컬럼 전용: reference_no 기준으로 그룹핑하여 대표 카드 목록 반환
  # 반환: [{order: Order, thread_count: Integer, is_thread: Boolean}]
  def build_inbox_groups(orders)
    orders.group_by { |o| o.reference_no.presence || "single_#{o.id}" }
          .map do |_key, group|
            { order: group.first, thread_count: group.size, is_thread: group.size > 1 }
          end
  end

  public

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
