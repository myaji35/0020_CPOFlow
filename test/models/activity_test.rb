# frozen_string_literal: true

require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "activity_model_test@example.com") do |u|
      u.name = "Activity Test User"; u.password = "password123"; u.role = :member
    end
    @order = Order.create!(title: "Activity Test Order", customer_name: "Cust", user: @user, status: :new_rfq)
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
  end

  test "Activity 생성 — action만으로 유효" do
    a = Activity.create!(order: @order, user: @user, action: "order_created")
    assert a.persisted?
    a.destroy
  end

  test "status_changed? — from/to 모두 있을 때 true" do
    a = Activity.new(
      order: @order, user: @user, action: "status_changed",
      from_status: Order.statuses[:new_rfq],
      to_status: Order.statuses[:make_quo]
    )
    assert a.status_changed?
  end

  test "status_changed? — from_status 없으면 false" do
    a = Activity.new(order: @order, user: @user, action: "order_created")
    assert_not a.status_changed?
  end

  test "from_label — new_rfq 상태 라벨 반환" do
    a = Activity.new(
      order: @order, user: @user, action: "status_changed",
      from_status: Order.statuses[:new_rfq],
      to_status: Order.statuses[:make_quo]
    )
    assert_not_nil a.from_label
  end

  test "to_label — make_quo 상태 라벨 반환" do
    a = Activity.new(
      order: @order, user: @user, action: "status_changed",
      from_status: Order.statuses[:new_rfq],
      to_status: Order.statuses[:make_quo]
    )
    assert_not_nil a.to_label
  end

  test "from_label — from_status nil이면 nil 반환" do
    a = Activity.new(order: @order, user: @user, action: "order_created")
    assert_nil a.from_label
  end

  test "recent scope — 최신순 정렬" do
    a1 = Activity.create!(order: @order, user: @user, action: "event_a", created_at: 5.minutes.ago)
    a2 = Activity.create!(order: @order, user: @user, action: "event_b", created_at: 1.minute.ago)
    ids = Activity.where(order: @order).recent.pluck(:id)
    assert_equal a2.id, ids.first
    a1.destroy; a2.destroy
  end
end
