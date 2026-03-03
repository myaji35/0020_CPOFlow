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
    @orders = @orders.joins(:assignments).where(assignments: { employee_id: params[:employee_id] }) if params[:employee_id].present?

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
    @filter_employees = Employee.active.by_name

    @total_count = @orders.count
    @orders = @orders.limit(50).offset((params[:page].to_i > 0 ? params[:page].to_i - 1 : 0) * 50)
    @current_page = [ params[:page].to_i, 1 ].max
    @total_pages = (@total_count / 50.0).ceil
  end

  def show
    @tasks    = @order.tasks.by_due.includes(:assignee)
    @comments = @order.comments.chronological.includes(:user)
    @activities = @order.activities.recent.includes(:user).limit(20)
    @team_members = Employee.active.by_name
    # 관련 메일 스레드: sub_orders 우선, 없으면 reference_no 기반 fallback
    @thread_orders = if @order.sub_orders.exists?
      @order.sub_orders.order(created_at: :asc)
    elsif @order.parent_order_id.present?
      Order.where(parent_order_id: @order.parent_order_id)
           .or(Order.where(id: @order.parent_order_id))
           .where.not(id: @order.id)
           .order(created_at: :asc)
    elsif @order.reference_no.present?
      Order.where(reference_no: @order.reference_no)
           .where.not(id: @order.id)
           .order(created_at: :asc)
    else
      Order.none
    end
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

      # 동일 gmail_thread_id의 inbox 상태 Order도 함께 변경
      synced_count = sync_thread_siblings_status(new_status)

      notice_msg = t("orders.status_updated", status: t("orders.status.#{new_status}", default: new_status))
      notice_msg += " (연관 #{synced_count}건도 함께 변경됨)" if synced_count > 0
      redirect_back fallback_location: kanban_path, notice: notice_msg
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

  def sync_thread_siblings_status(new_status)
    siblings = find_thread_siblings
    return 0 if siblings.empty?

    siblings.find_each do |sibling|
      old = sibling.status
      sibling.update!(status: new_status)
      Activity.create!(
        order: sibling,
        user: current_user,
        action: "status_changed",
        from_status: Order.statuses[old],
        to_status: Order.statuses[sibling.status]
      )
    end

    siblings.count
  end

  # gmail_thread_id 또는 제목의 이벤트 번호로 연관 inbox 건 탐색
  def find_thread_siblings
    base = Order.where(status: :inbox).where.not(id: @order.id)

    # 1순위: 동일 gmail_thread_id
    by_thread = base.where(gmail_thread_id: @order.gmail_thread_id) if @order.gmail_thread_id.present?
    return by_thread if by_thread.present? && by_thread.exists?

    # 2순위: 제목에서 숫자 이벤트 번호 추출 후 LIKE 검색
    event_number = @order.original_email_subject&.match(/\b(\d{8,})\b/)&.captures&.first
    return Order.none if event_number.blank?

    base.where("original_email_subject LIKE ?", "%#{event_number}%")
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
