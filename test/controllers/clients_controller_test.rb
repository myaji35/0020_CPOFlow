# frozen_string_literal: true

require "test_helper"

class ClientsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "clients_ctrl_test@example.com") do |u|
      u.name = "Clients Test User"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
    @client = Client.create!(name: "Test Client Corp.", code: "CLI-TEST-#{SecureRandom.hex(4)}", country: "KR")
  end

  def teardown
    @client.destroy if Client.exists?(@client.id)
  end

  test "clients index 200" do
    get clients_path
    assert_response :success
  end

  test "clients index — 발주처 이름 표시" do
    get clients_path
    assert_match "Test Client Corp.", response.body
  end

  test "clients show 200" do
    get client_path(@client)
    assert_response :success
  end

  test "new client form 200" do
    get new_client_path
    assert_response :success
  end

  test "clients create — 성공" do
    assert_difference("Client.count", 1) do
      post clients_path, params: { client: { name: "New Client ABC", code: "CLI-NEW-#{SecureRandom.hex(4)}", country: "KR" } }
    end
    Client.find_by(name: "New Client ABC")&.destroy
  end

  test "clients create — name 없으면 실패" do
    assert_no_difference("Client.count") do
      post clients_path, params: { client: { name: "", code: "CLI-FAIL-1", country: "KR" } }
    end
  end

  test "clients update — name 변경" do
    patch client_path(@client), params: { client: { name: "Updated Client" } }
    @client.reload
    assert_equal "Updated Client", @client.name
  end

  test "clients destroy — 삭제" do
    c = Client.create!(name: "Delete Me Client", code: "CLI-DEL-#{SecureRandom.hex(4)}", country: "KR")
    assert_difference("Client.count", -1) do
      delete client_path(c)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
