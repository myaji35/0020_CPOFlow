class TeamController < ApplicationController
  # ISS-381: MenuPermission DB 가드
  #  - :read   — index/show (역할별 조회 통제)
  #  - :update — update_role (역할 변경 — 코드 내부 admin? 가드와 이중)
  before_action -> { enforce_menu_permission!(:team, :read) },   only: %i[index show]
  before_action -> { enforce_menu_permission!(:team, :update) }, only: %i[update_role]
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

    # ISS-218: 최근 8주 × 팀원별 작업 부하 히트맵
    # 셀 값: 해당 주에 생성/배정된 활성 주문 수 (처리량 프록시)
    weeks = (7.downto(0)).map do |i|
      ws = (i.weeks.ago.to_date.beginning_of_week(:monday))
      { start: ws, end: ws.end_of_week(:monday), label: ws.strftime("%m/%d") }
    end
    @heatmap_weeks = weeks

    # Activity 기반: status_changed 발생 = 해당 주 처리량
    @heatmap_data = @members.map do |u|
      activity_raw = Activity.where(user_id: u.id, action: %w[status_changed updated created])
                             .where("created_at >= ?", weeks.first[:start].beginning_of_day)
                             .group("date(created_at)").count
      row = weeks.map do |w|
        count = 0
        (w[:start]..w[:end]).each { |d| count += activity_raw[d.to_s].to_i }
        count
      end
      {
        user: u,
        weekly_counts: row,
        total: row.sum,
        avg:   row.any? ? (row.sum.to_f / row.size).round(1) : 0
      }
    end.sort_by { |r| -r[:total] }

    # 히트맵 max (색상 스케일 정규화)
    @heatmap_max = [ @heatmap_data.flat_map { |r| r[:weekly_counts] }.max || 1, 1 ].max
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
    @activity_max = [ @daily_activity.map { |d| d[:count] }.max || 1, 1 ].max
    @activity_total = @daily_activity.sum { |d| d[:count] }
  end

  def update_role
    redirect_to team_index_path, alert: "권한이 없습니다." and return unless current_user.admin?

    previous_role = @member.role
    @member.update!(role: params[:role])

    # AUDIT-006: viewer → member/manager/admin 승격 시 사용자에게 알림
    if previous_role == "viewer" && @member.role != "viewer"
      role_label = I18n.t("activerecord.attributes.user.role_#{@member.role}", default: @member.role)
      Notification.create!(
        user: @member,
        notification_type: "role_promoted",
        title: "권한이 #{role_label}(으)로 승격되었습니다",
        body: "이제 #{role_label} 권한으로 모든 기능을 사용할 수 있습니다."
      )
    end

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
