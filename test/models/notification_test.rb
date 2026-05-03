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

  # AUDIT-008: notification_type presence 검증
  test "notification_type 없으면 invalid" do
    n = Notification.new(notification_type: nil)
    assert_not n.valid?
    assert_includes n.errors[:notification_type], "은(는) 필수입니다"
  end

  test "notification_type 있으면 presence 검증 통과" do
    n = Notification.new(notification_type: "system")
    n.valid?
    assert_empty n.errors[:notification_type]
  end
end
