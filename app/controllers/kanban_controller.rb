class KanbanController < ApplicationController
  def index
    @columns = Order::KANBAN_COLUMNS.map do |status|
      orders = scoped_orders.root_orders
                    .where(status: status)
                    .by_due_date
                    .includes(:assignees, :tasks, :user, :sub_orders)
      [ status, orders ]
    end.to_h
    @filter_employees = Employee.active.by_name

    # 중복 스레드 ID 목록 (병합대상 버튼용)
    @duplicate_thread_ids = scoped_orders.where(parent_order_id: nil)
                                 .where.not(gmail_thread_id: [ nil, "" ])
                                 .group(:gmail_thread_id)
                                 .having("COUNT(*) > 1")
                                 .pluck(:gmail_thread_id)

    # 병합 모드용: 스레드별 그룹화된 주문 목록
    @merge_groups = @duplicate_thread_ids.map do |tid|
      orders = Order.where(gmail_thread_id: tid, parent_order_id: nil)
                    .includes(:assignees, :client, :sub_orders)
                    .order(created_at: :asc)
      { thread_id: tid, orders: orders }
    end
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

  # PATCH /kanban/split/:id — 서브 주문을 다시 독립 카드로 분리
  def split
    order = Order.find(params[:id])
    parent = order.parent_order

    if order.parent_order_id.nil?
      render json: { success: false, error: "이미 독립 카드입니다." }, status: :unprocessable_entity
      return
    end

    order.update_columns(parent_order_id: nil)
    Activity.create!(order: order, user: current_user, action: "order_split")
    Activity.create!(order: parent, user: current_user, action: "order_split") if parent

    render json: { success: true, order_id: order.id }
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
        order: main_order, user: current_user, action: "order_merged"
      )
      merged << order.id
    end

    render json: { success: true, merged_ids: merged, main_id: main_order.id, sub_count: main_order.sub_orders.count }
  end
end
