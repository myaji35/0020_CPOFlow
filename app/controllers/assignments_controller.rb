class AssignmentsController < ApplicationController
  # ISS-261: viewer read-only — 담당자 배정/해제는 member 이상만
  before_action :require_member!
  before_action :set_order

  def create
    @assignment = @order.assignments.find_or_initialize_by(employee_id: params[:employee_id])
    if @assignment.new_record? && @assignment.save
      employee = @assignment.employee
      Activity.create!(order: @order, user: current_user, action: "assignee_added")
    end
    redirect_back fallback_location: order_path(@order)
  end

  def destroy
    assignment = @order.assignments.find(params[:id])
    employee = assignment.employee
    assignment.destroy
    Activity.create!(order: @order, user: current_user, action: "assignee_removed")
    redirect_back fallback_location: order_path(@order)
  end

  private

  def set_order
    # ISS-257: Branch 격리
    @order = scoped_orders.find(params[:order_id])
  end
end
