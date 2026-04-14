# frozen_string_literal: true

require "test_helper"

class Admin::EcountSyncControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "admin_ecount_test@example.com") do |u|
      u.name = "Admin Ecount User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
  end

  test "index 200" do
    get admin_ecount_sync_index_path
    assert_response :success
  end

  test "trigger — 잘못된 유형이면 redirect with alert" do
    post trigger_admin_ecount_sync_index_path, params: { sync_type: "invalid" }
    assert_response :redirect
    assert_match /잘못된/, flash[:alert]
  end

  test "trigger — products 유형 성공" do
    assert_enqueued_with(job: EcountProductSyncJob) do
      post trigger_admin_ecount_sync_index_path, params: { sync_type: "products" }
    end
    assert_response :redirect
  end

  test "trigger — customers 유형 성공" do
    assert_enqueued_with(job: EcountCustomerSyncJob) do
      post trigger_admin_ecount_sync_index_path, params: { sync_type: "customers" }
    end
    assert_response :redirect
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
