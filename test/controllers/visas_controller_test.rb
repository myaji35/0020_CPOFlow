# frozen_string_literal: true

require "test_helper"

class VisasControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "visas_ctrl_test@example.com") do |u|
      u.name = "Visas Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @employee = Employee.create!(name: "Visa Test Employee", nationality: "KR", employment_type: "regular")
  end

  def teardown
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "new visa form 200" do
    get new_employee_visa_path(@employee)
    assert_response :success
  end

  test "visas create — 성공" do
    assert_difference("Visa.count", 1) do
      post employee_visas_path(@employee), params: {
        visa: {
          visa_type: "Employment",
          issuing_country: "AE",
          visa_number: "VISA-TEST-#{SecureRandom.hex(4)}",
          issue_date: 1.year.ago.to_date,
          expiry_date: 2.years.from_now.to_date,
          status: "active"
        }
      }
    end
    Visa.order(created_at: :desc).first&.destroy
  end

  test "visas update — 상태 변경" do
    visa = Visa.create!(
      employee: @employee,
      visa_type: "Employment",
      issuing_country: "AE",
      expiry_date: 1.year.from_now.to_date,
      status: "active"
    )
    patch employee_visa_path(@employee, visa), params: { visa: { status: "expired" } }
    visa.reload
    assert_equal "expired", visa.status
    visa.destroy
  end

  test "visas destroy — 삭제" do
    visa = Visa.create!(
      employee: @employee,
      visa_type: "Tourist",
      issuing_country: "AE",
      expiry_date: 1.year.from_now.to_date,
      status: "active"
    )
    assert_difference("Visa.count", -1) do
      delete employee_visa_path(@employee, visa)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
