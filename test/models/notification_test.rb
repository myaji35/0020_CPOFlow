require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    I18n.locale = :ko
  end

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

  # ─────────────────────────────────────────
  # ISS-353 Phase 1 — T13 모델 테스트
  # ─────────────────────────────────────────

  # 헬퍼: 신규 사용자 생성
  def make_user(suffix = SecureRandom.hex(3))
    User.create!(
      email: "ntest_#{suffix}@example.com",
      password: "password123",
      name: "NTest #{suffix}",
      role: :member
    )
  end

  # 헬퍼: 신규 Order
  def make_order(owner)
    Order.create!(
      user: owner,
      title: "MentionTest Order #{SecureRandom.hex(3)}",
      customer_name: "Cust",
      status: :new_rfq
    )
  end

  test "mentions scope returns only mentioned type" do
    u = make_user
    o = make_order(u)
    m  = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "@u 확인")
    nm = Notification.create!(user: u, notifiable: o, notification_type: "due_date", body: "due")

    user_notifs = Notification.where(user: u)
    assert_equal 1, user_notifs.mentions.count
    assert_equal m.id, user_notifs.mentions.first.id
  ensure
    Notification.where(user: u).destroy_all if u
    o&.reload&.destroy
    u&.destroy
  end

  test "unacknowledged scope filters acknowledged_at IS NULL" do
    u = make_user
    o = make_order(u)
    a = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "1")
    b = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "2")
    a.update!(acknowledged_at: Time.current)

    rel = Notification.where(user: u).mentions.unacknowledged
    assert_equal 1, rel.count
    assert_equal b.id, rel.first.id
  ensure
    Notification.where(user: u).destroy_all if u
    o&.reload&.destroy
    u&.destroy
  end

  test "intent_level defaults to 0 on create" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    assert_equal 0, n.intent_level
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "acknowledge! sets acknowledged_at and read_at" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    assert_nil n.acknowledged_at
    assert_nil n.read_at

    before = Time.current
    n.acknowledge!(viewer: u)
    after = Time.current

    n.reload
    assert n.acknowledged_at.present?
    assert n.read_at.present?
    assert_in_delta before.to_f, n.acknowledged_at.to_f, (after - before + 1.0)
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "acknowledge! is idempotent — second call no-op" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    n.acknowledge!(viewer: u)
    first_ts = n.reload.acknowledged_at

    sleep 0.05  # ensure Time.current would differ
    n.acknowledge!(viewer: u)
    assert_equal first_ts.to_f, n.reload.acknowledged_at.to_f, "second acknowledge should not update timestamp"
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "acknowledge! rejects non-owner" do
    owner   = make_user("own")
    other   = make_user("oth")
    o = make_order(owner)
    n = Notification.create!(user: owner, notifiable: o, notification_type: "mentioned", body: "x")

    n.acknowledge!(viewer: other)
    assert_nil n.reload.acknowledged_at, "non-owner viewer must not set acknowledged_at"
  ensure
    n&.destroy
    o&.reload&.destroy
    owner&.destroy
    other&.destroy
  end

  test "mark_viewed! sets viewed_at and viewed_duration_sec" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    n.mark_viewed!(duration_sec: 5)
    n.reload
    assert n.viewed_at.present?
    assert_equal 5, n.viewed_duration_sec
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "mark_viewed! is idempotent" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    n.mark_viewed!(duration_sec: 5)
    first_ts = n.reload.viewed_at

    sleep 0.05
    n.mark_viewed!(duration_sec: 99)
    n.reload
    assert_equal first_ts.to_f, n.viewed_at.to_f, "second mark_viewed! must not update timestamp"
    assert_equal 5, n.viewed_duration_sec, "duration must not be overwritten"
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "after_commit triggers Order#recompute_mention_summary! for mentions only" do
    u = make_user
    o = make_order(u)
    assert_equal 0, o.reload.mention_total_count

    Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "@u 1")
    assert_equal 1, o.reload.mention_total_count, "mention notif should increment mention_total_count"

    Notification.create!(user: u, notifiable: o, notification_type: "due_date", body: "due")
    assert_equal 1, o.reload.mention_total_count, "non-mention notif must NOT change mention_total_count"
  ensure
    Notification.where(notifiable: o).destroy_all if o
    o&.reload&.destroy
    u&.destroy
  end

  test "after_commit no-op when notifiable destroyed_by_association" do
    u = make_user
    o = make_order(u)
    Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    # Order#destroy → has_many :notifications, dependent: :destroy → 자식 destroy 시
    # destroyed_by_association 가드로 broadcast/recompute 무발화 (raise 없이 정상 종료)
    assert_nothing_raised { o.reload.destroy }
    o = nil
  ensure
    o&.reload&.destroy if o && Order.exists?(o.id)
    u&.destroy
  end

  # ─────────────────────────────────────────
  # ISS-354 Phase 2 — T13 SLA + sent_by_user_id
  # ─────────────────────────────────────────

  test "Notification#assign_sla_due_at — intent 0 (FYI) → sla_due_at nil" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned",
                             intent_level: 0, body: "x")
    assert_nil n.sla_due_at, "intent 0 (FYI)는 SLA 없음"
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification#assign_sla_due_at — intent 1 (@@) → sla_due_at ~ 4시간 뒤" do
    u = make_user
    o = make_order(u)
    before = Time.current
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned",
                             intent_level: 1, body: "x")
    after = Time.current
    assert_not_nil n.sla_due_at
    expected = before + 4.hours
    expected_max = after + 4.hours
    assert n.sla_due_at >= expected - 1.second, "sla_due_at은 4시간 이후여야 함"
    assert n.sla_due_at <= expected_max + 1.second
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification#assign_sla_due_at — intent 2 (@@@) → sla_due_at ~ 1시간 뒤" do
    u = make_user
    o = make_order(u)
    before = Time.current
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned",
                             intent_level: 2, body: "x")
    after = Time.current
    assert_not_nil n.sla_due_at
    assert n.sla_due_at >= (before + 1.hour) - 1.second
    assert n.sla_due_at <= (after + 1.hour) + 1.second
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification#assign_sla_due_at — mentioned 타입에만 발화 (visa/contract 등 제외)" do
    u = make_user
    o = make_order(u)
    n_due = Notification.create!(user: u, notifiable: o, notification_type: "due_date",
                                 intent_level: 2, body: "x")
    assert_nil n_due.sla_due_at, "due_date 타입은 SLA 무발화"

    n_visa = Notification.create!(user: u, notifiable: o, notification_type: "visa",
                                  intent_level: 2, body: "y")
    assert_nil n_visa.sla_due_at, "visa 타입은 SLA 무발화"
  ensure
    n_due&.destroy
    n_visa&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification#assign_sla_due_at — 미리 set 된 sla_due_at 보존 (멱등)" do
    u = make_user
    o = make_order(u)
    fixed_due = 10.hours.from_now
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned",
                             intent_level: 2, sla_due_at: fixed_due, body: "x")
    # intent 2면 1시간 뒤로 자동 산출되겠지만, 이미 set이면 그 값 유지
    assert_in_delta fixed_due.to_f, n.sla_due_at.to_f, 1.0
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification#assign_default_intent_level — 기본값 0" do
    u = make_user
    o = make_order(u)
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned", body: "x")
    assert_equal 0, n.intent_level, "intent_level 미지정 시 기본 0"
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end

  test "Notification — sent_by_user_id is nullable (legacy 알림 호환)" do
    u = make_user
    o = make_order(u)
    # sent_by_user_id 미지정 (기존 Phase 1 알림 패턴) — 검증 통과해야 함
    n = Notification.create!(user: u, notifiable: o, notification_type: "mentioned",
                             intent_level: 0, body: "legacy")
    assert_nil n.sent_by_user_id
    assert n.persisted?, "sent_by_user_id 없이도 저장 가능해야 함"
  ensure
    n&.destroy
    o&.reload&.destroy
    u&.destroy
  end
end
