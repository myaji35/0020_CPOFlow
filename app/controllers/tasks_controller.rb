class TasksController < ApplicationController
  before_action :set_order

  def create
    @task = @order.tasks.build(task_params)
    @task.save
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("task-list-#{@order.id}",
            partial: "tasks/task", locals: { task: @task, order: @order }),
          turbo_stream.replace("task-progress-#{@order.id}",
            partial: "tasks/progress", locals: { order: @order }),
          turbo_stream.replace("task-add-form-#{@order.id}",
            partial: "tasks/add_form", locals: { order: @order })
        ]
      end
      format.html { redirect_to @order }
    end
  end

  def update
    @task = @order.tasks.find(params[:id])
    @task.update(task_params)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("task-#{@task.id}",
            partial: "tasks/task", locals: { task: @task, order: @order }),
          turbo_stream.replace("task-progress-#{@order.id}",
            partial: "tasks/progress", locals: { order: @order })
        ]
      end
      format.html { redirect_to @order }
    end
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
