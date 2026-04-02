require "test_helper"

class EmployeeTest < ActiveSupport::TestCase
  test "Employee EMPLOYMENT_TYPES 상수 존재" do
    assert defined?(Employee::EMPLOYMENT_TYPES), "EMPLOYMENT_TYPES 상수 누락"
    assert Employee::EMPLOYMENT_TYPES.is_a?(Array)
    assert Employee::EMPLOYMENT_TYPES.any?
  end

  test "Employee scopes 정상 동작" do
    assert_nothing_raised { Employee.active.count }
    assert_nothing_raised { Employee.by_name.limit(5).to_a }
    assert_nothing_raised { Employee.dispatched.count }
  end

  test "Employee associations 쿼리 정상" do
    assert_nothing_raised do
      Employee.includes(:user, :department).limit(5).to_a
    end
  end
end
