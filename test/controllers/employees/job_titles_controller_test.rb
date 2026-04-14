# frozen_string_literal: true

require "test_helper"

class Employees::JobTitlesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "emp_jobtitle_ctrl_test@example.com") do |u|
      u.name = "Emp JobTitle Ctrl User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
  end

  test "index JSON 200" do
    get employees_job_titles_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end

  test "create — 직책 생성 성공" do
    name = "테스트직책_#{SecureRandom.hex(4)}"
    assert_difference("JobTitle.count", 1) do
      post employees_job_titles_path, params: { name: name }, as: :json
    end
    assert_response :created
    JobTitle.find_by(name: name)&.destroy
  end

  test "create — 직책명 없으면 422" do
    assert_no_difference("JobTitle.count") do
      post employees_job_titles_path, params: { name: "" }, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "destroy — 존재하지 않는 ID는 404" do
    delete employees_job_title_path(999999), as: :json
    assert_response :not_found
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
