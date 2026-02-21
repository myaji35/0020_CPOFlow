class TasksController < ApplicationController
  before_action :set_order

  def create
    @task = @order.tasks.build(task_params)
    @task.save
    redirect_to @order
  end

  def update
    @task = @order.tasks.find(params[:id])
    @task.update(task_params)
    redirect_to @order
  end

  def destroy
    @order.tasks.find(params[:id]).destroy
    redirect_to @order
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end

  def task_params
    params.require(:task).permit(:title, :completed, :due_date, :assignee_id, :description)
  end
end
