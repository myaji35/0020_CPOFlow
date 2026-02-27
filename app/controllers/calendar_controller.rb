class CalendarController < ApplicationController
  def index
    @month  = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    @orders = Order.where(due_date: @month..@month.end_of_month)
                   .includes(:assignees, :client, :project)
                   .by_due_date

    today = Date.today
    @stats = {
      total:   @orders.count,
      overdue: @orders.count { |o| o.due_date < today },
      urgent:  @orders.count { |o| o.due_date >= today && o.due_date <= today + 7 },
      normal:  @orders.count { |o| o.due_date > today + 7 }
    }
  end
end
