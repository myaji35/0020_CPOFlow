require "test_helper"

class EmployeeExtendedTest < ActiveSupport::TestCase
  # initials 테스트
  test "initials: 두 글자 반환" do
    emp = Employee.new(name: "John Smith", nationality: "US", employment_type: "regular")
    assert_equal "JS", emp.initials
  end

  test "initials: 한 단어면 첫 글자만" do
    emp = Employee.new(name: "Alice", nationality: "US", employment_type: "regular")
    assert_equal "A", emp.initials
  end

  # avatar_color 테스트
  test "avatar_color: 한국 국적이면 bg-blue-500" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_equal "bg-blue-500", emp.avatar_color
  end

  test "avatar_color: 미지원 국적이면 bg-gray-500" do
    emp = Employee.new(name: "Test", nationality: "XX", employment_type: "regular")
    assert_equal "bg-gray-500", emp.avatar_color
  end

  # nationality_label 테스트
  test "nationality_label: KR이면 한국" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_equal "한국", emp.nationality_label
  end

  test "nationality_label: 미지원 코드면 코드 그대로 반환" do
    emp = Employee.new(name: "Test", nationality: "ZZ", employment_type: "regular")
    assert_equal "ZZ", emp.nationality_label
  end

  # employment_type_label 테스트
  test "employment_type_label: regular이면 정규직" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_equal "정규직", emp.employment_type_label
  end

  test "employment_type_label: contract이면 계약직" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "contract")
    assert_equal "계약직", emp.employment_type_label
  end

  test "employment_type_label: dispatch이면 파견" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "dispatch")
    assert_equal "파견", emp.employment_type_label
  end

  # display_name 테스트
  test "display_name: name 반환" do
    emp = Employee.new(name: "Jane Doe", nationality: "US", employment_type: "regular")
    assert_equal "Jane Doe", emp.display_name
  end

  # tenure_days 테스트
  test "tenure_days: hire_date 없으면 nil" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_nil emp.tenure_days
  end

  test "tenure_days: hire_date 있으면 양수" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular",
                       hire_date: 365.days.ago.to_date)
    assert emp.tenure_days > 0
  end

  # tenure_label 테스트
  test "tenure_label: hire_date 없으면 nil" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_nil emp.tenure_label
  end

  test "tenure_label: 1년 이상이면 '년 개월' 형식" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular",
                       hire_date: 400.days.ago.to_date)
    label = emp.tenure_label
    assert label.include?("년"), "Expected years in label: #{label}"
  end

  test "tenure_label: 1개월 이상 1년 미만이면 '개월' 형식" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular",
                       hire_date: 60.days.ago.to_date)
    label = emp.tenure_label
    assert label.include?("개월") || label.include?("일"), "Expected months/days in label: #{label}"
  end

  # visa_expiring_soon? 테스트
  test "visa_expiring_soon?: active_visa 없으면 false" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_equal false, emp.visa_expiring_soon?
  end

  # contract_expiring_soon? 테스트
  test "contract_expiring_soon?: current_contract 없으면 false" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "regular")
    assert_equal false, emp.contract_expiring_soon?
  end

  # validates 테스트
  test "Employee: name 없으면 invalid" do
    emp = Employee.new(nationality: "KR", employment_type: "regular")
    assert_not emp.valid?
    assert emp.errors[:name].any?
  end

  test "Employee: employment_type 목록 외 값이면 invalid" do
    emp = Employee.new(name: "Test", nationality: "KR", employment_type: "unknown")
    assert_not emp.valid?
  end

  test "Employee: 유효한 정보이면 valid" do
    emp = Employee.new(name: "Valid Employee", nationality: "KR", employment_type: "regular")
    assert emp.valid?
  end

  # NATIONALITIES 상수
  test "NATIONALITIES 상수에 주요 국가 포함" do
    assert Employee::NATIONALITIES.key?("KR")
    assert Employee::NATIONALITIES.key?("AE")
  end
end
