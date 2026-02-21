class TeamController < ApplicationController
  def index
    @members = User.order(:branch, :name).includes(:assigned_orders, :tasks)
    @workloads = @members.map do |u|
      active = u.assigned_orders.active.count
      { user: u, active_orders: active, tasks_pending: u.tasks.pending.count }
    end
  end

  def show
    @member = User.find(params[:id])
    @active_orders = @member.assigned_orders.active.by_due_date.limit(10)
  end
end
