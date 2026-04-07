# frozen_string_literal: true

require "test_helper"

class AssignmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "assignments_ctrl_test@example.com") do |u|
      u.name = "Assignments Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @employee = Employee.create!(name: "Assignee Test Employee", nationality: "KR", employment_type: "regular")
    @order = Order.create!(title: "Assignment Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "assignments create — 담당자 배정" do
    assert_difference("Assignment.count", 1) do
      post order_assignments_path(@order), params: { employee_id: @employee.id }
    end
  end

  test "assignments create — 중복 배정 방지 (idempotent)" do
    post order_assignments_path(@order), params: { employee_id: @employee.id }
    assert_no_difference("Assignment.count") do
      post order_assignments_path(@order), params: { employee_id: @employee.id }
    end
  end

  test "assignments destroy — 배정 해제" do
    assignment = Assignment.create!(order: @order, employee: @employee)
    assert_difference("Assignment.count", -1) do
      delete order_assignment_path(@order, assignment)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
