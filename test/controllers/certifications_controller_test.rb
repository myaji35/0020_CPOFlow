# frozen_string_literal: true

require "test_helper"

class CertificationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "certifications_ctrl_test@example.com") do |u|
      u.name = "Certifications Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @employee = Employee.create!(name: "Cert Test Employee", nationality: "KR", employment_type: "regular")
  end

  def teardown
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "new certification form 200" do
    get new_employee_certification_path(@employee)
    assert_response :success
  end

  test "certifications create — 성공" do
    assert_difference("Certification.count", 1) do
      post employee_certifications_path(@employee), params: {
        certification: { name: "PMP Certificate", issued_date: 1.year.ago.to_date }
      }
    end
    Certification.order(created_at: :desc).first&.destroy
  end

  test "certifications create — name 없으면 실패" do
    assert_no_difference("Certification.count") do
      post employee_certifications_path(@employee), params: {
        certification: { name: "" }
      }
    end
  end

  test "certifications update — name 변경" do
    cert = Certification.create!(employee: @employee, name: "Old Cert Name")
    patch employee_certification_path(@employee, cert), params: { certification: { name: "Updated Cert" } }
    cert.reload
    assert_equal "Updated Cert", cert.name
    cert.destroy
  end

  test "certifications destroy — 삭제" do
    cert = Certification.create!(employee: @employee, name: "Delete This Cert")
    assert_difference("Certification.count", -1) do
      delete employee_certification_path(@employee, cert)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
