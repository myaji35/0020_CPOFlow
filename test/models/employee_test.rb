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

  # AUDIT-005: unmapped scope + suggested_user 테스트
  test "Employee.unmapped scope — user_id nil인 직원만 반환" do
    assert_nothing_raised { Employee.unmapped.count }
    Employee.unmapped.each do |emp|
      assert_nil emp.user_id, "unmapped scope에 user_id가 있는 직원 포함됨: #{emp.name}"
    end
  end

  test "suggested_user — user_id 있으면 nil 반환" do
    emp = Employee.where.not(user_id: nil).first
    skip "연결된 직원 없음" unless emp
    assert_nil emp.suggested_user
  end

  test "suggested_user — user_id nil + email 매칭 시 User 반환" do
    user = User.first
    skip "User 없음" unless user
    emp  = Employee.new(name: "테스트직원", nationality: "KR", employment_type: "regular",
                        email: user.email, user_id: nil)
    result = emp.suggested_user
    assert_equal user.id, result&.id, "이메일 매칭 실패"
  end

  test "suggested_user — user_id nil + email 없고 이름 매칭 시 User 반환" do
    user = User.where.not(name: nil).first
    skip "이름 있는 User 없음" unless user
    emp = Employee.new(name: user.name, nationality: "KR", employment_type: "regular",
                       email: nil, user_id: nil)
    result = emp.suggested_user
    assert_equal user.id, result&.id, "이름 매칭 실패"
  end
end
