# frozen_string_literal: true

require "test_helper"

class EmployeesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "employees_ctrl_test@example.com") do |u|
      u.name = "Employees Test User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
    @employee = Employee.create!(
      name: "Test Employee",
      nationality: "KR",
      employment_type: "regular"
    )
  end

  def teardown
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "employees index 200" do
    get employees_path
    assert_response :success
  end

  test "employees index — 직원 이름 표시" do
    get employees_path
    assert_match "Test Employee", response.body
  end

  test "employees show 200" do
    get employee_path(@employee)
    assert_response :success
  end

  test "new employee form 200" do
    get new_employee_path
    assert_response :success
  end

  test "employees create — 성공" do
    assert_difference("Employee.count", 1) do
      post employees_path, params: {
        employee: { name: "New Employee", nationality: "US", employment_type: "contract" }
      }
    end
    Employee.find_by(name: "New Employee")&.destroy
  end

  test "employees create — name 없으면 실패" do
    assert_no_difference("Employee.count") do
      post employees_path, params: {
        employee: { name: "", nationality: "KR", employment_type: "regular" }
      }
    end
  end

  test "employees update — name 변경" do
    patch employee_path(@employee), params: {
      employee: { name: "Updated Employee" }
    }
    @employee.reload
    assert_equal "Updated Employee", @employee.name
  end

  test "employees destroy — 삭제" do
    e = Employee.create!(name: "Delete Me", nationality: "KR", employment_type: "regular")
    assert_difference("Employee.count", -1) do
      delete employee_path(e)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
