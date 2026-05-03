class KanbanController < ApplicationController
  # ISS-261: viewer read-only — 칸반 이동/병합/분리는 member 이상만
  before_action :require_member!, only: %i[move merge split]

  # ISS-046 후속: 칸반 컬럼별 첫 N건만 즉시 렌더, 나머지는 turbo-frame lazy로 백그라운드.
  # 8개 컬럼 × 평균 20~50건 = 첫 페이지 ~200건 인서트 부담 → INITIAL_LIMIT로 80% 단축.
  INITIAL_LIMIT = 20  # 컬럼당 즉시 렌더 카드 수
  PREFETCH_LIMIT = 80 # 컬럼당 백그라운드 추가 페치 상한

  def index
    perf_t0 = Time.now
    @prefetch_mode = params[:frame] == "prefetch"  # column lazy frame 요청 여부
    @prefetch_status = params[:status]             # 어느 컬럼을 prefetch?

    # 보드 로딩 (권한 필터링)
    @boards = KanbanBoard.ordered.select { |b| can_access_board?(b) }
    @current_board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first
    end
    @current_board ||= KanbanBoard.ensure_default!

    # 현재 보드 접근 권한 체크
    unless can_access_board?(@current_board)
      @current_board = @boards.first || KanbanBoard.ensure_default!
    end

    # prefetch 모드: 단일 컬럼의 추가 데이터만 반환
    if @prefetch_mode && @prefetch_status.present?
      load_single_column_more
      return
    end

    # 칼럼 목록: 기본 보드는 Order::KANBAN_COLUMNS, 커스텀 보드는 KanbanColumn에서
    if @current_board.is_default?
      @kanban_column_keys = Order::KANBAN_COLUMNS
    else
      @kanban_column_keys = @current_board.kanban_columns.ordered.pluck(:key)
      @kanban_column_keys = %w[todo in_progress completed] if @kanban_column_keys.empty?
    end
    @kanban_column_labels = if @current_board.is_default?
      Order::STATUS_LABELS
    else
      @current_board.kanban_columns.ordered.pluck(:key, :name).to_h
    end

    # WIP 제한 맵 (ISS-201): 커스텀 보드의 KanbanColumn.wip_limit 사용
    # 기본 보드는 status 기반이라 wip_limit 없음 → 빈 해시
    @wip_limits = if @current_board.is_default?
      {}
    else
      @current_board.kanban_columns.ordered.pluck(:key, :wip_limit).to_h.compact
    end

    # 서버 사이드 키워드 검색: params[:q] 있으면 전체 컬럼에 LIKE 필터 적용 + limit 해제
    @search_query = params[:q].to_s.strip
    search_active = @search_query.present?

    # 정상 로드: 모든 컬럼 첫 INITIAL_LIMIT건만
    # P1: eager load 슬림화 — 카드 파셜 미사용 :user 제거. tasks/comments/sub_orders 는
    # task_progress / comments.count / sub_orders.count 호출하므로 preload 유지(메모리 카운트로 N+1 회피).
    @column_totals = {}
    @columns = @kanban_column_keys.map do |col_key|
      base = board_scoped_orders
                    .root_orders
                    .by_due_date
                    .includes(:assignees, :tasks, :sub_orders, :card_status, :client, :project, :comments)

      relation = if @current_board.is_default? || @current_board.board_type == "purchase"
        # 구매보드: 기존 status 기반
        if col_key == "new_rfq"
          # new_rfq(접수함): 방금 등록한 발주가 맨 위로 — 최근 생성 우선
          # AUDIT-001: show_stale=true 시 전체 표시, 기본은 최근 30일만
          rfq_base = base.where(status: :new_rfq, rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
          rfq_base = rfq_base.recent_new_rfq unless params[:show_stale] == "true"
          rfq_base.reorder(created_at: :desc)
        else
          base.where(status: col_key)
        end
      else
        # 커스텀 보드: kanban_column.key 기반
        column = @current_board.kanban_columns.find_by(key: col_key)
        column ? base.where(kanban_column_id: column.id) : base.none
      end

      # 검색어 필터 (title / customer_name / reference_no / rfq_no / po_no)
      if search_active
        like = "%#{@search_query}%"
        relation = relation.where(
          "orders.title LIKE ? OR orders.customer_name LIKE ? OR " \
          "orders.reference_no LIKE ? OR orders.rfq_no LIKE ? OR orders.po_no LIKE ?",
          like, like, like, like, like
        )
      end

      col_limit = search_active ? 200 : INITIAL_LIMIT
      # P3: 병렬 쿼리 — load_async 로 컬럼 카드 fetch 와 count 를 동시 발사.
      # SQLite WAL 환경에서도 read 동시성 OK. 9컬럼 직렬 0.3초 → 병렬 ~0.4초 단발에 수렴.
      records_promise = relation.limit(col_limit).load_async
      count_promise   = relation.async_count
      @column_totals[col_key] = count_promise
      [ col_key, records_promise ]
    end.to_h

    # async 결과 수확 — to_a / value 호출 시점에 결과 대기
    @columns = @columns.transform_values(&:to_a)
    @column_totals = @column_totals.transform_values(&:value)

    # AUDIT-001: new_rfq 컬럼 stale/recent 카운트 (헤더 표시용)
    @new_rfq_recent_count = board_scoped_orders.recent_new_rfq
                              .where(rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
                              .count
    @new_rfq_stale_count  = board_scoped_orders.stale_new_rfq
                              .where(rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
                              .count

    @filter_employees = Employee.active.by_name
    @card_statuses = @current_board.card_statuses.order(:position)

    # Inbox 전용 그룹핑 (reference_no 기준)
    inbox_orders = @columns["inbox"] || []
    @inbox_grouped = build_inbox_groups(inbox_orders)

    # P2: 중복 스레드 / 병합 그룹은 첫 렌더에서 lazy 화 — merge=1 파라미터 또는 turbo-frame 진입 시만 fetch.
    # 운영 분포: 중복 thread 0건 → 무조건 100ms 소비하던 부담 제거.
    if params[:merge] == "1"
      @duplicate_thread_ids = board_scoped_orders
                                   .where(parent_order_id: nil)
                                   .where.not(gmail_thread_id: [ nil, "" ])
                                   .group(:gmail_thread_id)
                                   .having("COUNT(*) > 1")
                                   .pluck(:gmail_thread_id)

      @merge_groups = @duplicate_thread_ids.map do |tid|
        orders = Order.where(gmail_thread_id: tid, parent_order_id: nil)
                      .includes(:assignees, :client, :sub_orders)
                      .order(created_at: :asc)
        { thread_id: tid, orders: orders }
      end
    else
      @duplicate_thread_ids = []
      @merge_groups = []
    end

    elapsed_ms = ((Time.now - perf_t0) * 1000).round(1)
    initial_total = @columns.values.sum(&:size)
    Rails.logger.info "[PERF][kanban] initial=#{initial_total} columns=#{@columns.size} totals=#{@column_totals} ms=#{elapsed_ms}"
  end

  # turbo-frame lazy 응답 — 특정 컬럼의 INITIAL_LIMIT 이후 카드들
  def load_single_column_more
    status = @prefetch_status
    valid_key = if @current_board.is_default? || @current_board.board_type == "purchase"
      Order::KANBAN_COLUMNS.include?(status)
    else
      @current_board.kanban_columns.exists?(key: status)
    end
    return render(html: "", layout: false) unless valid_key

    base = board_scoped_orders
                  .root_orders
                  .by_due_date
                  .includes(:assignees, :tasks, :sub_orders, :card_status, :client, :project, :comments)

    relation = if @current_board.is_default? || @current_board.board_type == "purchase"
      if status == "new_rfq"
        # new_rfq(접수함): 최근 생성 우선 — index와 동일 정렬
        # AUDIT-001: show_stale=true 시 전체 표시, 기본은 최근 30일만
        rfq_base = base.where(status: :new_rfq, rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
        rfq_base = rfq_base.recent_new_rfq unless params[:show_stale] == "true"
        rfq_base.reorder(created_at: :desc)
      else
        base.where(status: status)
      end
    else
      column = @current_board.kanban_columns.find_by(key: status)
      column ? base.where(kanban_column_id: column.id) : base.none
    end

    @more_orders = relation.offset(INITIAL_LIMIT).limit(PREFETCH_LIMIT - INITIAL_LIMIT).to_a
    @prefetch_status_for_view = status
    Rails.logger.info "[PERF][kanban] prefetch column=#{status} more=#{@more_orders.size}"

    render partial: "kanban/column_more", locals: { status: status, orders: @more_orders }, layout: false
  end

  # GET /kanban/card/:id — 단일 카드 partial 재렌더 (담당자/상태/배지 변경 후 부분 갱신용)
  def card
    order = scoped_orders.includes(:assignees, :tasks, :sub_orders, :card_status, :client, :project, :comments).find(params[:id])
    render partial: "kanban/card", locals: { order: order }, layout: false
  rescue ActiveRecord::RecordNotFound
    render html: "", layout: false, status: :not_found
  end

  def move
    @order = scoped_orders.find(params[:id])
    board = @order.kanban_board

    if board.nil? || board.is_default? || board.board_type == "purchase"
      # 구매보드(기본): 기존 status enum 이동
      old_status = @order.status
      # ISS-265: admin은 상태 전이 규칙 우회 (데이터 정정 목적)
      @order.force_transition = true if current_user.admin?
      if @order.update(status: params[:status])
        Activity.create!(
          order: @order,
          user: current_user,
          action: "status_changed",
          from_status: Order.statuses[old_status],
          to_status: Order.statuses[@order.status]
        )

        # ISS-293: new_rfq → make_quo 전환 시 RFP 자동 분석 Job 트리거
        rfp_triggered = false
        if old_status.to_s == "new_rfq" && @order.status.to_s == "make_quo"
          Rfp::AnalyzeAttachmentsJob.perform_later(@order.id)
          rfp_triggered = true
          Rails.logger.info("[ISS-293] RFP 분석 Job enqueued for order=#{@order.id}")
        end

        render json: {
          success: true,
          new_status: @order.status,
          column_counts: build_column_counts(board),
          rfp_analysis_triggered: rfp_triggered
        }
      else
        render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
      end
    else
      # 커스텀 보드: kanban_column_id 이동
      column = KanbanColumn.find_by(kanban_board_id: board.id, key: params[:status])
      if column && @order.update(kanban_column_id: column.id)
        Activity.create!(order: @order, user: current_user, action: "column_moved")
        render json: { success: true, new_status: column.key, column_counts: build_column_counts(board) }
      else
        render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  # PATCH /kanban/split/:id — 서브 주문을 다시 독립 카드로 분리
  def split
    order = scoped_orders.find(params[:id])
    parent = order.parent_order

    if order.parent_order_id.nil?
      render json: { success: false, error: "이미 독립 카드입니다." }, status: :unprocessable_entity
      return
    end

    order.update_columns(parent_order_id: nil)

    # ISS-275: split 후에도 원본↔자식 이력 추적 유지 — derived_from 링크 생성
    # parent_order_id FK는 끊지만 OrderLink로 논리적 족보 보존 (감사/thread 추적)
    if parent
      begin
        OrderLink.create!(
          source: parent,
          target: order,
          relation: "derived_from",
          status: "confirmed",
          confidence: 1.0,
          created_by: current_user,
          metadata: {
            source: "kanban_split",
            trigger: "manual_split",
            actor: current_user.email,
            split_at: Time.current.iso8601
          }
        )
      rescue => e
        Rails.logger.warn "[ISS-275] split OrderLink 생성 실패 order##{order.id} parent##{parent.id}: #{e.class}: #{e.message}"
      end
    end

    Activity.create!(order: order, user: current_user, action: "order_split")
    Activity.create!(order: parent, user: current_user, action: "order_split") if parent

    render json: { success: true, order_id: order.id }
  end

  private

  # move 응답용: 각 칼럼의 최신 카운트를 반환
  def build_column_counts(board)
    board ||= @current_board || KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    base = if board.is_default?
      scoped_orders.where(kanban_board_id: [ board.id, nil ])
    else
      scoped_orders.where(kanban_board_id: board.id)
    end.root_orders

    if board.is_default? || board.board_type == "purchase"
      Order::KANBAN_COLUMNS.each_with_object({}) do |col_key, h|
        rel = if col_key == "new_rfq"
          base.where(status: :new_rfq, rfq_status: Order::KANBAN_VISIBLE_RFQ_STATUSES)
        else
          base.where(status: col_key)
        end
        h[col_key] = rel.count
      end
    else
      board.kanban_columns.ordered.each_with_object({}) do |col, h|
        h[col.key] = base.where(kanban_column_id: col.id).count
      end
    end
  end

  # 현재 보드에 속한 주문만 필터. 기본 보드이면 kanban_board_id=nil도 포함.
  def board_scoped_orders
    if @current_board.is_default?
      scoped_orders.where(kanban_board_id: [ @current_board.id, nil ])
    else
      scoped_orders.where(kanban_board_id: @current_board.id)
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

    main_order = scoped_orders.find(main_id)
    merged = []

    merge_ids.each do |oid|
      order = scoped_orders.find_by(id: oid)
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
