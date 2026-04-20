# frozen_string_literal: true

require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "users_ctrl_test@example.com") do |u|
      u.name = "Users Ctrl Test"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
  end

  test "mention_suggestions — 빈 q 파라미터 JSON" do
    get mention_suggestions_path, params: { q: "" }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end

  test "mention_suggestions — 검색어 JSON" do
    get mention_suggestions_path, params: { q: "test" }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
  end

  test "빈 쿼리여도 Employee 결과 있으면 포함 (드롭다운 즉시 표시)" do
    target_user = User.find_or_create_by(email: "mention_api_employee_target@example.com") do |u|
      u.name = "Mention API Emp"; u.password = "password123"; u.role = :member
    end
    emp = Employee.find_or_create_by(name: "멘션API테스트직원") do |e|
      e.nationality = "KR"; e.employment_type = "regular"; e.active = true
    end
    emp.update!(user_id: target_user.id)

    get mention_suggestions_path, params: { q: "" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |i| i["display_name"] == "멘션API테스트직원" },
           "빈 쿼리에서도 Employee 결과 반환돼야 함: #{body.inspect}"
  ensure
    emp&.destroy
    target_user&.destroy
  end

  test "Employee 미등록 User도 fallback source:user 로 포함" do
    target_user = User.find_or_create_by(email: "fallback_only_user@example.com") do |u|
      u.name = "FallbackOnly User"; u.password = "password123"; u.role = :member
    end

    get mention_suggestions_path, params: { q: "FallbackOnly" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    hit = body.find { |i| i["display_name"] == "FallbackOnly User" }
    assert hit, "Employee 없는 User도 결과에 포함돼야 함: #{body.inspect}"
    assert_equal "user", hit["source"]
  ensure
    target_user&.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
