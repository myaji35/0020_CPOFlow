# frozen_string_literal: true

require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "comments_ctrl_test@example.com") do |u|
      u.name = "Comments Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @order = Order.create!(title: "Comment Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
  end

  test "comments create — 성공 (HTML)" do
    assert_difference("Comment.count", 1) do
      post order_comments_path(@order), params: { body: "새 코멘트 내용" }
    end
    comment = Comment.order(created_at: :desc).first
    assert_equal "새 코멘트 내용", comment.body
    comment.destroy
  end

  test "comments create — 빈 body 시 저장되지 않음" do
    assert_no_difference("Comment.count") do
      post order_comments_path(@order), params: { body: "" }
    end
  end

  test "comments create — Turbo Stream 응답" do
    post order_comments_path(@order),
         params: { body: "Turbo 코멘트" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    comment = Comment.order(created_at: :desc).first
    comment&.destroy
  end

  test "comments destroy — 삭제 성공" do
    comment = Comment.create!(body: "삭제할 코멘트", order: @order, user: @user)
    assert_difference("Comment.count", -1) do
      delete order_comment_path(@order, comment)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
