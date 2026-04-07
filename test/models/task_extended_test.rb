require "test_helper"

class TaskExtendedTest < ActiveSupport::TestCase
  test "Task: title 없으면 invalid" do
    task = Task.new(order_id: 1)
    assert_not task.valid?
    assert task.errors[:title].any?
  end

  test "Task: title 255자 초과이면 invalid" do
    task = Task.new(title: "a" * 256, order_id: 1)
    assert_not task.valid?
  end

  test "Task: 유효한 task는 valid" do
    task = Task.new(title: "Valid Task")
    task.valid?
    # order 없어서 invalid이지만 title은 문제 없음
    assert task.errors[:title].empty?
  end

  test "overdue?: completed이면 false" do
    task = Task.new(title: "Test", completed: true, due_date: 1.day.ago.to_date)
    assert_equal false, task.overdue?
  end

  test "overdue?: due_date 없으면 false" do
    task = Task.new(title: "Test", completed: false, due_date: nil)
    assert_equal false, task.overdue?
  end

  test "overdue?: 미완료 + 과거 due_date이면 true" do
    task = Task.new(title: "Test", completed: false, due_date: 1.day.ago.to_date)
    assert_equal true, task.overdue?
  end

  test "overdue?: 미완료 + 미래 due_date이면 false" do
    task = Task.new(title: "Test", completed: false, due_date: 1.day.from_now.to_date)
    assert_equal false, task.overdue?
  end

  test "pending scope 동작" do
    assert_nothing_raised { Task.pending.count }
  end

  test "done scope 동작" do
    assert_nothing_raised { Task.done.count }
  end

  test "by_due scope 동작" do
    assert_nothing_raised { Task.by_due.limit(5).to_a }
  end
end
