# frozen_string_literal: true

require "test_helper"

class OrgChart::CompaniesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "org_companies_ctrl_test@example.com") do |u|
      u.name = "Org Companies Ctrl User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)

    @country = Country.first || Country.create!(name: "Test Country OC", name_en: "Test Country OC EN", code: "OC")
    @company = Company.create!(name: "Test Company #{SecureRandom.hex(4)}", company_type: "hq", country: @country, active: true)
  end

  def teardown
    @company.destroy if Company.exists?(@company.id)
    Company.where("name LIKE 'New Company%' OR name LIKE 'Destroy Company%'").destroy_all
  end

  test "index 200" do
    get org_chart_companies_path
    assert_response :success
  end

  test "show 200" do
    get org_chart_company_path(@company)
    assert_response :success
  end

  test "new 200" do
    get new_org_chart_company_path
    assert_response :success
  end

  test "create — 성공" do
    assert_difference("Company.count", 1) do
      post org_chart_companies_path, params: {
        company: { name: "New Company #{SecureRandom.hex(4)}", company_type: "branch", country_id: @country.id, active: true }
      }
    end
    assert_response :redirect
  end

  test "edit 200" do
    get edit_org_chart_company_path(@company)
    assert_response :success
  end

  test "update — 이름 변경" do
    patch org_chart_company_path(@company), params: {
      company: { name: "Updated Company Name" }
    }
    assert_response :redirect
    assert_equal "Updated Company Name", @company.reload.name
  end

  test "destroy — 삭제" do
    c = Company.create!(name: "Destroy Company #{SecureRandom.hex(4)}", company_type: "hq", country: @country, active: true)
    assert_difference("Company.count", -1) do
      delete org_chart_company_path(c)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
