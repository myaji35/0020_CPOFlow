# frozen_string_literal: true

require "test_helper"

class EmploymentContractsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "employment_contracts_ctrl_test@example.com") do |u|
      u.name = "Employment Contract Test User"; u.password = "password123"; u.role = :manager  # ISS-300: 비자/고용계약은 민감정보 — manager 이상만 CRUD.
      # 권한 강화 시 컨트롤러만 바꾸고 테스트는 :member로 남아 302 리다이렉트로 깨졌다.
    end
    login_as(@user)
    @employee = Employee.create!(name: "Contract Test Employee", nationality: "KR", employment_type: "regular")
  end

  def teardown
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "new employment_contract form 200" do
    get new_employee_employment_contract_path(@employee)
    assert_response :success
  end

  test "employment_contracts create — 성공" do
    assert_difference("EmploymentContract.count", 1) do
      post employee_employment_contracts_path(@employee), params: {
        employment_contract: {
          start_date: 1.year.ago.to_date,
          status: "active",
          currency: "KRW",
          pay_frequency: "monthly"
        }
      }
    end
    EmploymentContract.order(created_at: :desc).first&.destroy
  end

  test "employment_contracts create — start_date 없으면 실패" do
    assert_no_difference("EmploymentContract.count") do
      post employee_employment_contracts_path(@employee), params: {
        employment_contract: { start_date: nil, status: "active" }
      }
    end
  end

  test "employment_contracts update — status 변경" do
    contract = EmploymentContract.create!(employee: @employee, start_date: 1.year.ago.to_date, status: "active")
    patch employee_employment_contract_path(@employee, contract), params: {
      employment_contract: { status: "expired" }
    }
    contract.reload
    assert_equal "expired", contract.status
    contract.destroy
  end

  test "employment_contracts destroy — 삭제" do
    contract = EmploymentContract.create!(employee: @employee, start_date: 1.year.ago.to_date, status: "active")
    assert_difference("EmploymentContract.count", -1) do
      delete employee_employment_contract_path(@employee, contract)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
