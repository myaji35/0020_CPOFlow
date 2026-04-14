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

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
