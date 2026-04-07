require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  def setup
    # 테스트 유저 생성 또는 재사용
    @user = User.find_or_create_by(email: "test_integration@example.com") do |u|
      u.name     = "Integration Test User"
      u.password = "password123"
      u.role     = :member
    end
  end

  test "로그인 페이지 접근 가능" do
    get new_user_session_path
    assert_response :success
  end

  test "미인증 상태로 kanban 접근 시 리다이렉트" do
    get kanban_path
    assert_redirected_to new_user_session_path
  end

  test "미인증 상태로 orders 접근 시 리다이렉트" do
    get orders_path
    assert_redirected_to new_user_session_path
  end

  test "미인증 상태로 dashboard 접근 시 리다이렉트" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "유효하지 않은 자격증명으로 로그인 실패" do
    post user_session_path, params: {
      user: { email: "nonexistent@example.com", password: "wrongpassword" }
    }
    assert_response :unprocessable_entity
  end

  test "로그아웃 후 보호된 페이지 접근 불가" do
    sign_in @user
    delete destroy_user_session_path
    get kanban_path
    assert_redirected_to new_user_session_path
  end

  private

  def sign_in(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
