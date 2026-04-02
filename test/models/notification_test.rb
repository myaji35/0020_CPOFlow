require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "Notification scopes 정상 동작" do
    assert_nothing_raised { Notification.unread.count }
    assert_nothing_raised { Notification.recent.limit(10).to_a }
  end

  test "Notification read? 메서드 응답" do
    n = Notification.new(read_at: nil)
    assert_equal false, n.read?
    n.read_at = Time.current
    assert_equal true, n.read?
  end

  test "Notification associations 쿼리 정상" do
    assert_nothing_raised do
      Notification.includes(:user).limit(5).to_a
    end
  end
end
