class CalendarController < ApplicationController
  def index
    @month = params[:month] ? Date.parse(params[:month]) : Date.today.beginning_of_month
    @orders = Order.where(due_date: @month..@month.end_of_month)
                   .includes(:assignees)
                   .by_due_date
  end
end
