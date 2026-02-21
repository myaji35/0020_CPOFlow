class AssignmentsController < ApplicationController
  before_action :set_order

  def create
    @assignment = @order.assignments.find_or_initialize_by(user_id: params[:user_id])
    @assignment.save
    redirect_to @order
  end

  def destroy
    @order.assignments.find(params[:id]).destroy
    redirect_to @order
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
