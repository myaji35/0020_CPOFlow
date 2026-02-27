class TeamController < ApplicationController
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

    @summary = {
      total_members: @members.count,
      total_active:  @workloads.sum { |w| w[:active_orders] },
      total_overdue: @workloads.sum { |w| w[:overdue_orders] },
      overloaded:    @workloads.count { |w| w[:active_orders] >= 8 }
    }
  end

  def show
    @member         = User.find(params[:id])
    @overdue_orders = @member.assigned_orders.overdue.by_due_date
                             .includes(:client, :project)
    @active_orders  = @member.assigned_orders.active
                             .where("due_date >= ? OR due_date IS NULL", Date.today)
                             .by_due_date.limit(20)
                             .includes(:client, :project)
    @status_counts  = @member.assigned_orders.group(:status).count
  end

  def update_role
    redirect_to team_index_path, alert: "권한이 없습니다." and return unless current_user.admin?

    @member = User.find(params[:id])
    @member.update!(role: params[:role])
    redirect_to team_index_path, notice: "#{@member.display_name} 역할이 변경되었습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to team_index_path, alert: "변경 실패: #{e.message}"
  end
end
