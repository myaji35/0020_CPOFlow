require "test_helper"

class CardStatus::AutoAssignerTest < ActiveSupport::TestCase
  fixtures :card_statuses

  setup do
    @urgent = card_statuses(:urgent)
    @high   = card_statuses(:high)
    @normal = card_statuses(:normal)
  end

  test "returns urgent when due within 3 days" do
    order = Order.new(due_date: Date.current + 2)
    assert_equal @urgent, CardStatus::AutoAssigner.call(order)
  end

  test "returns high when due within 7 days but not 3" do
    order = Order.new(due_date: Date.current + 5)
    assert_equal @high, CardStatus::AutoAssigner.call(order)
  end

  test "returns default(normal) when no rule matches" do
    order = Order.new(due_date: Date.current + 30)
    assert_equal @normal, CardStatus::AutoAssigner.call(order)
  end

  test "returns default when due_date nil" do
    order = Order.new(due_date: nil)
    assert_equal @normal, CardStatus::AutoAssigner.call(order)
  end

  test "higher auto_priority wins when multiple rules match" do
    order = Order.new(due_date: Date.current + 2)
    assert_equal @urgent, CardStatus::AutoAssigner.call(order)
  end
end
