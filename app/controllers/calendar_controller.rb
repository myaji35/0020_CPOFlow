class CalendarController < ApplicationController
  def index
    @view = %w[monthly weekly].include?(params[:view]) ? params[:view] : "monthly"
    @month = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    today  = Date.today

    if @view == "weekly"
      @week_start = params[:date] ? Date.parse(params[:date]).beginning_of_week(:sunday) : today.beginning_of_week(:sunday)
      @week_end   = @week_start + 6.days
      @orders = Order.where(due_date: @week_start..@week_end)
                     .includes(:assignees, :client, :project, :card_status)
                     .by_due_date
    else
      first_day  = @month.beginning_of_month
      grid_start = first_day - first_day.wday.days
      grid_end   = grid_start + 41.days
      @orders = Order.where(due_date: grid_start..grid_end)
                     .includes(:assignees, :client, :project, :card_status)
                     .by_due_date
    end

    # 통계: 이번 달 기준
    month_start = @month.beginning_of_month
    month_end   = @month.end_of_month
    month_orders = @orders.select { |o| o.due_date >= month_start && o.due_date <= month_end }
    @stats = {
      total:     month_orders.count,
      overdue:   month_orders.count { |o| o.due_date < today && !o.done? },
      this_week: month_orders.count { |o| o.due_date >= today.beginning_of_week(:sunday) && o.due_date <= today.end_of_week(:sunday) },
      completed: month_orders.count { |o| o.done? || o.get_grn? }
    }
  end
end
