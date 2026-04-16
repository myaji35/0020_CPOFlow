class KanbanController < ApplicationController
  # ISS-046 후속: 칸반 컬럼별 첫 N건만 즉시 렌더, 나머지는 turbo-frame lazy로 백그라운드.
  # 8개 컬럼 × 평균 20~50건 = 첫 페이지 ~200건 인서트 부담 → INITIAL_LIMIT로 80% 단축.
  INITIAL_LIMIT = 20  # 컬럼당 즉시 렌더 카드 수
  PREFETCH_LIMIT = 80 # 컬럼당 백그라운드 추가 페치 상한

  def index
    perf_t0 = Time.now
    @prefetch_mode = params[:frame] == "prefetch"  # column lazy frame 요청 여부
    @prefetch_status = params[:status]             # 어느 컬럼을 prefetch?

    # 보드 로딩
    @boards = KanbanBoard.ordered
    @current_board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first
    end
    @current_board ||= KanbanBoard.ensure_default!

    # prefetch 모드: 단일 컬럼의 추가 데이터만 반환
    if @prefetch_mode && @prefetch_status.present?
      load_single_column_more
      return
    end

    # 정상 로드: 모든 컬럼 첫 INITIAL_LIMIT건만
    @column_totals = {}
    @columns = Order::KANBAN_COLUMNS.map do |status|
      base = board_scoped_orders
                    .root_orders
                    .by_due_date
                    .includes(:assignees, :tasks, :user, :sub_orders)
      relation = if status == "new_rfq"
        base.where(status: :new_rfq, rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
      else
        base.where(status: status)
      end
      total = relation.count
      @column_totals[status] = total
      [ status, relation.limit(INITIAL_LIMIT).to_a ]
    end.to_h
    @filter_employees = Employee.active.by_name
    @card_statuses = @current_board.card_statuses.order(:position)

    # Inbox 전용 그룹핑 (reference_no 기준)
    inbox_orders = @columns["inbox"] || []
    @inbox_grouped = build_inbox_groups(inbox_orders)

    # 중복 스레드 ID 목록 (병합대상 버튼용)
    @duplicate_thread_ids = board_scoped_orders
                                 .where(parent_order_id: nil)
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

    elapsed_ms = ((Time.now - perf_t0) * 1000).round(1)
    initial_total = @columns.values.sum(&:size)
    Rails.logger.info "[PERF][kanban] initial=#{initial_total} columns=#{@columns.size} totals=#{@column_totals} ms=#{elapsed_ms}"
  end

  # turbo-frame lazy 응답 — 특정 컬럼의 INITIAL_LIMIT 이후 카드들
  def load_single_column_more
    status = @prefetch_status
    return render(html: "", layout: false) unless Order::KANBAN_COLUMNS.include?(status)

    base = board_scoped_orders
                  .root_orders
                  .by_due_date
                  .includes(:assignees, :tasks, :user, :sub_orders)
    relation = if status == "new_rfq"
      base.where(status: :new_rfq, rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
    else
      base.where(status: status)
    end

    @more_orders = relation.offset(INITIAL_LIMIT).limit(PREFETCH_LIMIT - INITIAL_LIMIT).to_a
    @prefetch_status_for_view = status
    Rails.logger.info "[PERF][kanban] prefetch column=#{status} more=#{@more_orders.size}"

    render partial: "kanban/column_more", locals: { status: status, orders: @more_orders }, layout: false
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

  private

  # 현재 보드에 속한 주문만 필터. 기본 보드이면 kanban_board_id=nil도 포함.
  def board_scoped_orders
    if @current_board.is_default?
      scoped_orders.where(kanban_board_id: [ @current_board.id, nil ])
    else
      board_scoped_orders
    end
  end

  # Inbox 컬럼 전용: reference_no 기준 그룹핑
  # reference_no 있는 그룹 → 대표 카드 1개 + thread_count
  # reference_no 없는 단건 → 그대로
  def build_inbox_groups(orders)
    groups = orders.group_by { |o| o.reference_no.presence || "single_#{o.id}" }
    groups.map do |_key, group_orders|
      representative = group_orders.first
      thread_count   = group_orders.size
      { order: representative, thread_count: thread_count, is_thread: thread_count > 1 }
    end
  end

  public

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
