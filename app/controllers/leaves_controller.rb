class LeavesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_member!
  before_action :set_leave, only: %i[show edit update destroy approve_manager approve_admin reject cancel]

  # GET /leaves
  def index
    @tab = params[:tab].presence_in(%w[mine pending all]) || "mine"

    base = Leave.includes(:employee).order(requested_at: :desc)

    @leaves = case @tab
              when "pending"
                require_manager_inline { return } || base.pending
              when "all"
                require_admin_inline { return } || base
              else
                # "mine" — 연결된 employee의 휴가만
                my_employee = Employee.find_by(user_id: current_user.id)
                my_employee ? base.where(employee: my_employee) : base.none
              end

    @pagy, @leaves = pagy(@leaves, items: 30) if respond_to?(:pagy)
  end

  # GET /leaves/:id
  def show; end

  # GET /leaves/new
  def new
    @leave = Leave.new
    @employee = my_employee
  end

  # POST /leaves
  def create
    @employee = my_employee
    unless @employee
      redirect_to leaves_path, alert: t("leaves.errors.no_employee")
      return
    end

    @leave = @employee.leaves.new(leave_params)
    @leave.requested_at = Time.current

    if @leave.save
      notify_manager(@leave)
      redirect_to @leave, notice: t("leaves.notices.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /leaves/:id/edit
  def edit
    authorize_own_leave!
  end

  # PATCH /leaves/:id
  def update
    authorize_own_leave!
    if @leave.update(leave_params)
      redirect_to @leave, notice: t("leaves.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /leaves/:id
  def destroy
    require_admin_or_own!
    @leave.destroy!
    redirect_to leaves_path, notice: t("leaves.notices.deleted")
  end

  # PATCH /leaves/:id/approve_manager
  def approve_manager
    require_manager!
    @leave.update!(
      status: "manager_approved",
      manager_approved_by: current_user,
      manager_approved_at: Time.current
    )
    notify_admin(@leave)
    redirect_to @leave, notice: t("leaves.notices.manager_approved")
  end

  # PATCH /leaves/:id/approve_admin
  def approve_admin
    require_admin!
    @leave.update!(
      status: "approved",
      admin_approved_by: current_user,
      admin_approved_at: Time.current
    )
    notify_requester(@leave, :approved)
    redirect_to @leave, notice: t("leaves.notices.approved")
  end

  # PATCH /leaves/:id/reject
  def reject
    require_manager!
    @leave.update!(
      status: "rejected",
      rejected_by: current_user,
      rejected_at: Time.current,
      rejection_reason: params[:rejection_reason]
    )
    notify_requester(@leave, :rejected)
    redirect_to @leave, notice: t("leaves.notices.rejected")
  end

  # PATCH /leaves/:id/cancel
  def cancel
    unless @leave.employee.user_id == current_user.id || current_user.admin?
      redirect_to @leave, alert: t("leaves.errors.unauthorized")
      return
    end
    @leave.update!(status: "cancelled")
    redirect_to leaves_path, notice: t("leaves.notices.cancelled")
  end

  # GET /leaves/calendar — FullCalendar JSON
  def calendar
    from = params[:start]&.to_date || Date.current.beginning_of_month
    to   = params[:end]&.to_date   || Date.current.end_of_month

    leaves = Leave.approved.for_calendar(from, to).includes(:employee)

    events = leaves.map do |l|
      {
        id:    "leave-#{l.id}",
        title: "#{l.employee.name} (#{l.leave_type_label})",
        start: l.start_date.iso8601,
        end:   (l.end_date + 1).iso8601,
        color: l.leave_type_color,
        url:   leave_path(l),
        allDay: true
      }
    end

    render json: events
  end

  # GET /leaves/balance
  def balance
    require_manager!
    @employees = Employee.active.includes(:leaves).by_name
  end

  private

  def set_leave
    @leave = Leave.find(params[:id])
  end

  def leave_params
    params.require(:leave).permit(:leave_type, :start_date, :end_date, :days_requested, :reason, documents: [])
  end

  def my_employee
    Employee.find_by(user_id: current_user.id)
  end

  def authorize_own_leave!
    return if current_user.admin? || @leave.employee.user_id == current_user.id
    redirect_to leaves_path, alert: t("leaves.errors.unauthorized")
  end

  def require_admin_or_own!
    return if current_user.admin? || @leave.employee.user_id == current_user.id
    redirect_to leaves_path, alert: t("leaves.errors.unauthorized")
  end

  def require_manager_inline(&block)
    return true if current_user.admin_or_manager?
    redirect_to leaves_path, alert: t("leaves.errors.manager_required")
    false
  end

  def require_admin_inline(&block)
    return true if current_user.admin?
    redirect_to leaves_path, alert: t("leaves.errors.admin_required")
    false
  end

  def notify_manager(leave)
    # manager/admin 역할 사용자들에게 알림
    User.where(role: %w[manager admin]).find_each do |mgr|
      Notification.create!(
        user: mgr,
        notifiable: leave,
        title: t("leaves.notifications.new_request_title", name: leave.employee.name),
        body: t("leaves.notifications.new_request_body",
                name: leave.employee.name,
                type: leave.leave_type_label,
                from: leave.start_date.strftime("%Y-%m-%d"),
                to: leave.end_date.strftime("%Y-%m-%d")),
        notification_type: "system"
      ) rescue nil
    end
  end

  def notify_admin(leave)
    User.where(role: "admin").find_each do |admin|
      Notification.create!(
        user: admin,
        notifiable: leave,
        title: t("leaves.notifications.manager_approved_title", name: leave.employee.name),
        body: t("leaves.notifications.manager_approved_body", name: leave.employee.name),
        notification_type: "system"
      ) rescue nil
    end
  end

  def notify_requester(leave, result)
    requester_user = leave.employee.user
    return unless requester_user

    Notification.create!(
      user: requester_user,
      notifiable: leave,
      title: t("leaves.notifications.#{result}_title"),
      body: t("leaves.notifications.#{result}_body",
              from: leave.start_date.strftime("%Y-%m-%d"),
              to: leave.end_date.strftime("%Y-%m-%d")),
      notification_type: "system"
    ) rescue nil
  end
end
