class CalendarController < ApplicationController
  def index
    @month     = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    first_day  = @month.beginning_of_month
    grid_start = first_day - first_day.wday.days
    grid_end   = grid_start + 41.days

    @orders = Order.where(due_date: grid_start..grid_end)
                   .includes(:assignees, :client, :project)
                   .by_due_date

    today        = Date.today
    month_orders = @orders.select { |o| o.due_date.month == @month.month && o.due_date.year == @month.year }
    @stats = {
      total:   month_orders.count,
      overdue: month_orders.count { |o| o.due_date < today },
      urgent:  month_orders.count { |o| o.due_date >= today && o.due_date <= today + 7 },
      normal:  month_orders.count { |o| o.due_date > today + 7 }
    }
  end
end
