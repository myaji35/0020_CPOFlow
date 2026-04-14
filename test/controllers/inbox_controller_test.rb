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

  test "destroy — archived_at 설정 + redirect" do
    client = Client.create!(name: "Inbox Del Client", code: "IDCL#{SecureRandom.hex(3)}")
    order = Order.create!(
      title: "Inbox Del Test",
      customer_name: "Del Customer",
      client: client,
      status: :new_rfq,
      user: @user,
      original_email_from: "sender@example.com",
      original_email_subject: "Test"
    )

    assert_nil order.archived_at
    delete delete_inbox_email_path(order)
    assert_response :redirect
    assert order.reload.archived_at.present?

    # archived 는 inbox에 다시 보이지 않음
    get inbox_path
    assert_response :success
    assert_not_includes response.body, "Inbox Del Test"

    order.destroy
    client.destroy
  end

  test "destroy — turbo_stream 응답 시 row 제거" do
    client = Client.create!(name: "Inbox TS Client", code: "ITCL#{SecureRandom.hex(3)}")
    order = Order.create!(
      title: "Inbox TS Test",
      customer_name: "TS Customer",
      client: client,
      status: :new_rfq,
      user: @user,
      original_email_from: "sender@example.com"
    )

    delete delete_inbox_email_path(order), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "email-item-#{order.id}"

    order.destroy
    client.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
