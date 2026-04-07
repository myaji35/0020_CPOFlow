# frozen_string_literal: true

require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.find_or_create_by(email: "reports_ctrl_test@example.com") do |u|
      u.name = "Reports Test Admin"; u.password = "password123"; u.role = :admin
    end
    @admin.update!(role: :admin)
    login_as(@admin)
  end

  test "reports index 200" do
    get reports_path
    assert_response :success
  end

  test "reports index — this_month period" do
    get reports_path, params: { period: "this_month" }
    assert_response :success
  end

  test "reports index — last_month period" do
    get reports_path, params: { period: "last_month" }
    assert_response :success
  end

  test "reports index — this_year period" do
    get reports_path, params: { period: "this_year" }
    assert_response :success
  end

  test "reports index — custom period" do
    get reports_path, params: {
      period: "custom",
      from: 1.month.ago.strftime("%Y-%m-%d"),
      to: Date.today.strftime("%Y-%m-%d")
    }
    assert_response :success
  end

  test "reports export_csv" do
    get reports_export_csv_path, params: { period: "this_month" }, headers: { "Accept" => "text/csv" }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
