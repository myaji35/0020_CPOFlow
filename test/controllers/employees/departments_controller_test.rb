# frozen_string_literal: true

require "test_helper"

class Employees::DepartmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "emp_dept_ctrl_test@example.com") do |u|
      u.name = "Emp Dept Ctrl User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)

    country = Country.first || Country.create!(name: "Test Country Dept", name_en: "Test Country Dept EN", code: "TD")
    @company = Company.first || Company.create!(name: "Test Company", company_type: "hq", country: country)
  end

  test "index JSON 200" do
    get employees_departments_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end

  test "create — 부서 생성 성공" do
    assert_difference("Department.count", 1) do
      post employees_departments_path,
           params: { company_id: @company.id, name: "테스트부서_#{SecureRandom.hex(4)}" },
           as: :json
    end
    assert_response :created
    Department.where(company: @company).where("name LIKE ?", "테스트부서%").destroy_all
  end

  test "create — 부서명 없으면 422" do
    assert_no_difference("Department.count") do
      post employees_departments_path,
           params: { company_id: @company.id, name: "" },
           as: :json
    end
    assert_response :unprocessable_entity
  end

  test "destroy — 존재하지 않는 ID는 404" do
    delete employees_department_path(999999), as: :json
    assert_response :not_found
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
