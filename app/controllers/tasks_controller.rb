class TasksController < ApplicationController
  # ISS-261: viewer read-only — 할 일 생성/변경/삭제는 member 이상만
  before_action :require_member!
  before_action :set_order

  def create
    @task = @order.tasks.build(task_params)
    if @task.save
      MentionParserService.new(@task, current_user).call
    end
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
    title_changed = task_params[:title].present? && task_params[:title] != @task.title
    @task.update(task_params)
    if title_changed
      MentionParserService.new(@task, current_user).call
    end
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

  # ISS-293: RFP 자동 생성 태스크 👍/👎 피드백
  # PATCH /orders/:order_id/tasks/:id/feedback
  # params[:score] = "1" (좋음) | "-1" (나쁨) | "0" (취소)
  def feedback
    @task = @order.tasks.find(params[:id])
    score = params[:score].to_i
    # 같은 값을 다시 누르면 nil로 토글 (취소)
    new_score = (@task.feedback_score == score) ? nil : score.nonzero?
    @task.update_column(:feedback_score, new_score)

    render json: {
      success: true,
      task_id: @task.id,
      feedback_score: @task.feedback_score
    }
  end

  private

  def set_order
    # ISS-257: Branch 격리
    @order = scoped_orders.find(params[:order_id])
  end

  def task_params
    params.require(:task).permit(:title, :completed, :due_date, :assignee_id, :description)
  end
end
