# frozen_string_literal: true

require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "tasks_ctrl_test@example.com") do |u|
      u.name = "Tasks Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @order = Order.create!(title: "Task Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
  end

  test "tasks create — 성공 (HTML)" do
    assert_difference("Task.count", 1) do
      post order_tasks_path(@order), params: { task: { title: "새 태스크", completed: false } }
    end
    Task.find_by(title: "새 태스크", order: @order)&.destroy
  end

  test "tasks create — Turbo Stream 응답" do
    post order_tasks_path(@order),
         params: { task: { title: "Turbo 태스크", completed: false } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    Task.find_by(title: "Turbo 태스크", order: @order)&.destroy
  end

  test "tasks update — completed 변경 (HTML)" do
    task = Task.create!(title: "Complete Me", order: @order, completed: false)
    patch order_task_path(@order, task), params: { task: { completed: true } }
    task.reload
    assert task.completed
    task.destroy
  end

  test "tasks destroy — 삭제" do
    task = Task.create!(title: "Delete This Task", order: @order)
    assert_difference("Task.count", -1) do
      delete order_task_path(@order, task)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
