# frozen_string_literal: true

require "test_helper"

class CommentTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "comment_model_test@example.com") do |u|
      u.name = "Comment Test User"; u.password = "password123"; u.role = :member
    end
    @order = Order.create!(title: "Comment Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
  end

  test "body 없으면 유효하지 않음" do
    c = Comment.new(body: "", order: @order, user: @user)
    assert_not c.valid?
    assert_includes c.errors[:body], "can't be blank"
  end

  test "body 5000자 초과 시 유효하지 않음" do
    c = Comment.new(body: "A" * 5001, order: @order, user: @user)
    assert_not c.valid?
  end

  test "body 5000자는 유효" do
    c = Comment.new(body: "A" * 5000, order: @order, user: @user)
    assert c.valid?
  end

  test "order 없으면 유효하지 않음" do
    c = Comment.new(body: "Test", user: @user)
    assert_not c.valid?
  end

  test "user 없으면 유효하지 않음" do
    c = Comment.new(body: "Test", order: @order)
    assert_not c.valid?
  end

  test "정상 생성" do
    c = Comment.create!(body: "정상 코멘트", order: @order, user: @user)
    assert c.persisted?
    c.destroy
  end

  test "recent scope — 최신 먼저 정렬" do
    c1 = Comment.create!(body: "First", order: @order, user: @user, created_at: 2.minutes.ago)
    c2 = Comment.create!(body: "Second", order: @order, user: @user, created_at: 1.minute.ago)
    ids = Comment.where(order: @order).recent.pluck(:id)
    assert_equal c2.id, ids.first
    c1.destroy; c2.destroy
  end

  test "chronological scope — 오래된 것 먼저 정렬" do
    c1 = Comment.create!(body: "First", order: @order, user: @user, created_at: 2.minutes.ago)
    c2 = Comment.create!(body: "Second", order: @order, user: @user, created_at: 1.minute.ago)
    ids = Comment.where(order: @order).chronological.pluck(:id)
    assert_equal c1.id, ids.first
    c1.destroy; c2.destroy
  end
end
