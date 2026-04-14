# frozen_string_literal: true

require "test_helper"

class Admin::DuplicateOrdersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "admin_dup_orders_test@example.com") do |u|
      u.name = "Admin Dup Orders User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
  end

  test "index 200" do
    get admin_duplicate_orders_path
    assert_response :success
  end

  test "merge — main_id 없으면 redirect with alert" do
    post merge_admin_duplicate_orders_path, params: { main_order_id: 0, merge_order_ids: [] }
    assert_response :redirect
    assert_match /선택/, flash[:alert]
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
