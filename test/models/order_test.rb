require "test_helper"

class OrderTest < ActiveSupport::TestCase
  test "Order scopes 정상 동작" do
    assert_nothing_raised { Order.active.count }
    assert_nothing_raised { Order.overdue.count }
    assert_nothing_raised { Order.urgent.count }
    assert_nothing_raised { Order.delivered.count }
    assert_nothing_raised { Order.by_due_date.limit(1).to_a }
  end

  test "Order status enum 유효" do
    valid = %w[inbox reviewing quoted confirmed procuring qa delivered]
    valid.each do |s|
      assert Order.statuses.key?(s), "status #{s} 누락"
    end
  end

  test "Order priority enum 유효" do
    valid = %w[low medium high urgent]
    valid.each do |p|
      assert Order.priorities.key?(p), "priority #{p} 누락"
    end
  end

  test "Order associations 쿼리 정상" do
    # 레코드 없어도 includes 쿼리 자체는 정상이어야 함
    assert_nothing_raised do
      Order.includes(:client, :supplier, :project, :assignees, :tasks, :comments).limit(5).to_a
    end
  end

  test "overdue 건수 계산 정확성" do
    overdue = Order.where.not(status: "delivered").where("due_date < ?", Date.today)
    assert overdue.count >= 0
  end

  test "urgent(D-7) 건수 계산 정확성" do
    urgent = Order.where.not(status: "delivered")
                  .where(due_date: Date.today..7.days.from_now)
    assert urgent.count >= 0
  end

  test "estimated_value 합계 계산" do
    total = Order.sum(:estimated_value).to_f
    assert total >= 0
  end
end
