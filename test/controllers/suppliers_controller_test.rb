# frozen_string_literal: true

require "test_helper"

class SuppliersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "suppliers_ctrl_test@example.com") do |u|
      u.name = "Suppliers Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @supplier = Supplier.create!(name: "Test Supplier Co.")
  end

  def teardown
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "suppliers index 200" do
    get suppliers_path
    assert_response :success
  end

  test "suppliers index — 거래처 이름 표시" do
    get suppliers_path
    assert_match "Test Supplier Co.", response.body
  end

  test "suppliers show 200" do
    get supplier_path(@supplier)
    assert_response :success
  end

  test "new supplier form 200" do
    get new_supplier_path
    assert_response :success
  end

  test "suppliers create — 성공" do
    assert_difference("Supplier.count", 1) do
      post suppliers_path, params: { supplier: { name: "New Supplier XYZ" } }
    end
    Supplier.find_by(name: "New Supplier XYZ")&.destroy
  end

  test "suppliers create — name 없으면 실패" do
    assert_no_difference("Supplier.count") do
      post suppliers_path, params: { supplier: { name: "" } }
    end
  end

  test "suppliers update — name 변경" do
    patch supplier_path(@supplier), params: { supplier: { name: "Updated Supplier" } }
    @supplier.reload
    assert_equal "Updated Supplier", @supplier.name
  end

  test "suppliers show — 거래처 이름 헤더 표시" do
    get supplier_path(@supplier)
    assert_match "Test Supplier Co.", response.body
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
