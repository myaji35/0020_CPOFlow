class TeamController < ApplicationController
  def index
    @members = User.order(:branch, :name).includes(:assigned_orders, :tasks)
    today = Date.today

    @workloads = @members.map do |u|
      active = u.assigned_orders.active.to_a
      {
        user:           u,
        active_orders:  active.count,
        tasks_pending:  u.tasks.pending.count,
        overdue_orders: active.count { |o| o.due_date && o.due_date < today },
        urgent_orders:  active.count { |o| o.due_date && o.due_date >= today && o.due_date <= today + 7 }
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
end
