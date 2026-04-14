# frozen_string_literal: true

require "test_helper"

class OrgChart::DepartmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "org_depts_ctrl_test@example.com") do |u|
      u.name = "Org Depts Ctrl User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)

    @country = Country.first || Country.create!(name: "Test Country OD", name_en: "Test Country OD EN", code: "OD")
    @company = Company.create!(name: "Test Dept Company #{SecureRandom.hex(4)}", company_type: "hq", country: @country, active: true)
    @department = @company.departments.create!(name: "Test Dept #{SecureRandom.hex(4)}", active: true)
  end

  def teardown
    @department.destroy if Department.exists?(@department.id)
    @company.destroy if Company.exists?(@company.id)
  end

  test "show 200" do
    get org_chart_company_department_path(@company, @department)
    assert_response :success
  end

  test "new 200" do
    get new_org_chart_company_department_path(@company)
    assert_response :success
  end

  test "create — 성공" do
    assert_difference("Department.count", 1) do
      post org_chart_company_departments_path(@company), params: {
        department: { name: "New Dept #{SecureRandom.hex(4)}", active: true }
      }
    end
    assert_response :redirect
  end

  test "edit 200" do
    get edit_org_chart_company_department_path(@company, @department)
    assert_response :success
  end

  test "update — 이름 변경" do
    patch org_chart_company_department_path(@company, @department), params: {
      department: { name: "Updated Dept Name" }
    }
    assert_response :redirect
    assert_equal "Updated Dept Name", @department.reload.name
  end

  test "destroy — 삭제" do
    d = @company.departments.create!(name: "Destroy Dept #{SecureRandom.hex(4)}", active: true)
    assert_difference("Department.count", -1) do
      delete org_chart_company_department_path(@company, d)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
