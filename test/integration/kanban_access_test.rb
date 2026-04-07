require "test_helper"

class KanbanAccessTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "kanban_test@example.com") do |u|
      u.name     = "Kanban Test User"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)
  end

  test "kanban 페이지 접근 성공" do
    get kanban_path
    assert_response :success
  end

  test "orders 목록 페이지 접근 성공" do
    get orders_path
    assert_response :success
  end

  test "dashboard 페이지 접근 성공" do
    get dashboard_path
    assert_response :success
  end

  test "새 주문 폼 접근 성공" do
    get new_order_path
    assert_response :success
  end

  test "clients 목록 접근 성공" do
    get clients_path
    assert_response :success
  end

  test "suppliers 목록 접근 성공" do
    get suppliers_path
    assert_response :success
  end

  test "employees 목록 접근 성공" do
    get employees_path
    assert_response :success
  end

  test "projects 목록 접근 성공" do
    get projects_path
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
