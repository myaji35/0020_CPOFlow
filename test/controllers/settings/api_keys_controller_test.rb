# frozen_string_literal: true

require "test_helper"

class Settings::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_apikeys_test@example.com") do |u|
      u.name = "Settings ApiKeys User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "update — API Key 저장" do
    patch settings_api_keys_path, params: { anthropic_api_key: "sk-test-key-1234" }
    assert_response :redirect
    assert flash[:notice].present?
  end

  test "update — 빈 키는 삭제" do
    patch settings_api_keys_path, params: { anthropic_api_key: "" }
    assert_response :redirect
    assert flash[:notice].present?
  end

  test "verify JSON — 상태 반환" do
    post settings_verify_api_key_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("status")
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
