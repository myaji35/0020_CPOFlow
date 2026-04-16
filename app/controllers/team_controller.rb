class TeamController < ApplicationController
  before_action :set_member, only: %i[show update_role]

  def index
    branch = params[:branch].presence
    scope  = User.order(:branch, :name).includes(:assigned_orders, :tasks)
    scope  = scope.where(branch: branch) if branch.present?
    @members = scope

    today = Date.today

    @workloads = @members.map do |u|
      active  = u.assigned_orders.active.to_a
      nearest = active.select { |o| o.due_date.present? }
                      .min_by { |o| o.due_date }
      {
        user:           u,
        active_orders:  active.count,
        tasks_pending:  u.tasks.pending.count,
        overdue_orders: active.count { |o| o.due_date && o.due_date < today },
        urgent_orders:  active.count { |o| o.due_date && o.due_date >= today && o.due_date <= today + 7 },
        nearest_due:    nearest&.due_date
      }
    end

    total_active  = @workloads.sum { |w| w[:active_orders] }
    total_overdue = @workloads.sum { |w| w[:overdue_orders] }
    member_count  = @members.count

    @summary = {
      total_members: member_count,
      total_active:  total_active,
      total_overdue: total_overdue,
      overloaded:    @workloads.count { |w| w[:active_orders] >= 8 },
      avg_per_member: member_count > 0 ? (total_active.to_f / member_count).round(1) : 0,
      overdue_rate:   total_active > 0 ? (total_overdue.to_f / total_active * 100).round(1) : 0
    }

    # 담당자별 활성 주문 분포 (bar chart 데이터)
    @member_order_dist = @workloads
      .sort_by { |w| -w[:active_orders] }
      .map { |w| { name: w[:user].display_name, active: w[:active_orders], overdue: w[:overdue_orders] } }
  end

  def show
    @overdue_orders = @member.assigned_orders.overdue.by_due_date
                             .includes(:client, :project)
    @active_orders  = @member.assigned_orders.active
                             .where("due_date >= ? OR due_date IS NULL", Date.today)
                             .by_due_date.limit(20)
                             .includes(:client, :project)
    @status_counts  = @member.assigned_orders.group(:status).count

    # 최근 30일 일별 처리 건수 (status_changed 활동)
    thirty_days_ago = 30.days.ago.beginning_of_day
    daily_raw = Activity.where(user_id: @member.id)
                        .where(action: "status_changed")
                        .where("created_at >= ?", thirty_days_ago)
                        .group("date(created_at)")
                        .count

    @daily_activity = (0..29).map do |i|
      day = (Date.today - (29 - i))
      { date: day, count: daily_raw[day.to_s] || 0 }
    end
    @activity_max = [@daily_activity.map { |d| d[:count] }.max || 1, 1].max
    @activity_total = @daily_activity.sum { |d| d[:count] }
  end

  def update_role
    redirect_to team_index_path, alert: "권한이 없습니다." and return unless current_user.admin?

    @member.update!(role: params[:role])
    redirect_to team_index_path, notice: "#{@member.display_name} 역할이 변경되었습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to team_index_path, alert: "변경 실패: #{e.message}"
  end

  private

  def set_member
    @member = User.find_by(id: params[:id])
    unless @member
      redirect_to team_index_path, alert: "멤버를 찾을 수 없습니다."
    end
  end
end
