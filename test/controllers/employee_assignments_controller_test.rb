# frozen_string_literal: true

require "test_helper"

class EmployeeAssignmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "emp_assign_ctrl_test@example.com") do |u|
      u.name = "Emp Assign Ctrl User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)

    @employee = Employee.create!(
      name: "테스트직원-#{SecureRandom.hex(4)}",
      nationality: "KR",
      employment_type: "regular"
    )
    @client = Client.create!(name: "EmpAssign Client", code: "EACLI#{SecureRandom.hex(3)}")
    @project = Project.create!(
      name: "테스트프로젝트",
      code: "PROJ-ASSIGN-#{SecureRandom.hex(4)}",
      status: :active,
      client: @client
    )
  end

  def teardown
    @employee&.employee_assignments&.destroy_all
    @employee&.destroy
    @project&.destroy
    @client&.destroy
  end

  test "new 200" do
    get new_employee_employee_assignment_path(@employee)
    assert_response :success
  end

  test "create — 성공" do
    assert_difference("EmployeeAssignment.count", 1) do
      post employee_employee_assignments_path(@employee), params: {
        employee_assignment: {
          project_id: @project.id,
          role: "Developer",
          start_date: Date.today
        }
      }
    end
    assert_response :redirect
  end

  test "create — 실패 (project 없음)" do
    assert_no_difference("EmployeeAssignment.count") do
      post employee_employee_assignments_path(@employee), params: {
        employee_assignment: { project_id: nil, role: "" }
      }
    end
  end

  test "edit 200" do
    assignment = @employee.employee_assignments.create!(
      project: @project, role: "Dev", start_date: Date.today
    )
    get edit_employee_employee_assignment_path(@employee, assignment)
    assert_response :success
  end

  test "update — 성공" do
    assignment = @employee.employee_assignments.create!(
      project: @project, role: "Dev", start_date: Date.today
    )
    patch employee_employee_assignment_path(@employee, assignment), params: {
      employee_assignment: { role: "Lead" }
    }
    assert_response :redirect
    assert_equal "Lead", assignment.reload.role
  end

  test "destroy — 삭제" do
    assignment = @employee.employee_assignments.create!(
      project: @project, role: "Dev", start_date: Date.today
    )
    assert_difference("EmployeeAssignment.count", -1) do
      delete employee_employee_assignment_path(@employee, assignment)
    end
    assert_response :redirect
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
