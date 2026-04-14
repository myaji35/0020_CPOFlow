# frozen_string_literal: true

require "test_helper"

class OrgChart::CountriesControllerTest < ActionDispatch::IntegrationTest
  # 2자리 고유 코드 생성 헬퍼
  COUNTRY_CODES = ("AA".."ZZ").select { |c| c.match?(/\A[A-Z]{2}\z/) }.freeze

  def setup
    @user = User.find_or_create_by(email: "org_countries_ctrl_test@example.com") do |u|
      u.name = "Org Countries Ctrl User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)

    code = unused_country_code
    @country = Country.create!(name: "Test Country #{code}", name_en: "Test Country EN #{code}", code: code)
  end

  def teardown
    @country.destroy if Country.exists?(@country.id)
    Country.where("name LIKE 'New Country%' OR name LIKE 'Destroy Country%'").destroy_all
  end

  test "index 200" do
    get org_chart_countries_path
    assert_response :success
  end

  test "show 200" do
    get org_chart_country_path(@country)
    assert_response :success
  end

  test "new 200" do
    get new_org_chart_country_path
    assert_response :success
  end

  test "create — 성공" do
    code = unused_country_code
    assert_difference("Country.count", 1) do
      post org_chart_countries_path, params: {
        country: { name: "New Country #{code}", name_en: "New Country EN #{code}", code: code }
      }
    end
    assert_response :redirect
  end

  test "edit 200" do
    get edit_org_chart_country_path(@country)
    assert_response :success
  end

  test "update — 이름 변경" do
    patch org_chart_country_path(@country), params: { country: { name: "Updated Country" } }
    assert_response :redirect
    assert_equal "Updated Country", @country.reload.name
  end

  test "destroy — 삭제" do
    code = unused_country_code
    c = Country.create!(name: "Destroy Country #{code}", name_en: "Destroy Country EN #{code}", code: code)
    assert_difference("Country.count", -1) do
      delete org_chart_country_path(c)
    end
  end

  private

  def unused_country_code
    used = Country.pluck(:code).to_set
    COUNTRY_CODES.find { |c| !used.include?(c) } || "XX"
  end

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
