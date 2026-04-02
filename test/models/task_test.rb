require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "Task scopes 정상 동작" do
    assert_nothing_raised { Task.pending.count }
    assert_nothing_raised { Task.done.count }
    assert_nothing_raised { Task.by_due.limit(10).to_a }
  end

  test "Task associations 쿼리 정상" do
    assert_nothing_raised do
      Task.includes(:order, :assignee).limit(5).to_a
    end
  end

  test "pending + done 합계가 전체와 일치" do
    assert_equal Task.count, Task.pending.count + Task.done.count
  end
end
