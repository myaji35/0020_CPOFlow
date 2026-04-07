# frozen_string_literal: true

require "test_helper"

class InboxControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "inbox_ctrl_test@example.com") do |u|
      u.name = "Inbox Test User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "inbox index 200" do
    get inbox_path
    assert_response :success
  end

  test "inbox index — filter all" do
    get inbox_path, params: { filter: "all" }
    assert_response :success
  end

  test "inbox index — filter rfq" do
    get inbox_path, params: { filter: "rfq" }
    assert_response :success
  end

  test "inbox index — filter uncertain" do
    get inbox_path, params: { filter: "uncertain" }
    assert_response :success
  end

  test "inbox index — filter converted" do
    get inbox_path, params: { filter: "converted" }
    assert_response :success
  end

  test "inbox index — 검색 파라미터" do
    get inbox_path, params: { q: "test search" }
    assert_response :success
  end

  test "inbox index — 페이지네이션" do
    get inbox_path, params: { page: 2 }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
