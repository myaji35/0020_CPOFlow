class KanbanController < ApplicationController
  def index
    @columns = Order::KANBAN_COLUMNS.map do |status|
      orders = Order.root_orders
                    .where(status: status)
                    .by_due_date
                    .includes(:assignees, :tasks, :user, :sub_orders)
      [ status, orders ]
    end.to_h
    @filter_employees = Employee.active.by_name

    # 중복 스레드 ID ���록 (병합대상 버튼용)
    @duplicate_thread_ids = Order.where(parent_order_id: nil)
                                 .where.not(gmail_thread_id: [ nil, "" ])
                                 .group(:gmail_thread_id)
                                 .having("COUNT(*) > 1")
                                 .pluck(:gmail_thread_id)
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

  # POST /kanban/merge — 선택한 카드를 메인에 병합
  def merge
    main_id   = params[:main_order_id].to_i
    merge_ids = Array(params[:merge_order_ids]).map(&:to_i).reject { |id| id == main_id }

    if main_id.zero? || merge_ids.empty?
      render json: { success: false, error: "메인 주문과 병합 대상을 선택해 주세요." }, status: :unprocessable_entity
      return
    end

    main_order = Order.find(main_id)
    merged = []

    merge_ids.each do |oid|
      order = Order.find_by(id: oid)
      next unless order
      next if order.parent_order_id.present?

      order.sub_orders.update_all(parent_order_id: main_order.id)
      order.update_columns(parent_order_id: main_order.id)

      Activity.create!(
        order: main_order, user: current_user, action: "order_merged",
        metadata: { merged_order_id: order.id, merged_title: order.title }.to_json
      )
      merged << order.id
    end

    render json: { success: true, merged_ids: merged, main_id: main_order.id, sub_count: main_order.sub_orders.count }
  end
end
