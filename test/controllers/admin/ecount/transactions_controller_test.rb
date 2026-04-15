# frozen_string_literal: true

require "test_helper"

class Admin::Ecount::TransactionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by!(email: "ecount_txn_ctrl@example.com") do |u|
      u.name = "Ecount Txn Test"; u.password = "password123"; u.role = :admin
    end
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "index — 200 응답" do
    get admin_ecount_transactions_path
    assert_response :success
  end

  test "index — 검색 파라미터 적용" do
    get admin_ecount_transactions_path, params: { q: "search_term" }
    assert_response :success
  end
end
