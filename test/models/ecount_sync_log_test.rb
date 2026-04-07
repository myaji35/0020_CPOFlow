# frozen_string_literal: true

require "test_helper"

class EcountSyncLogTest < ActiveSupport::TestCase
  test "sync_type 유효 값 — products/customers/slip" do
    %w[products customers slip].each do |t|
      log = EcountSyncLog.new(sync_type: t, status: :pending)
      assert log.valid?, "#{t} should be valid"
    end
  end

  test "sync_type 없으면 invalid" do
    log = EcountSyncLog.new(sync_type: nil, status: :pending)
    assert_not log.valid?
  end

  test "sync_type 잘못된 값이면 invalid" do
    log = EcountSyncLog.new(sync_type: "unknown", status: :pending)
    assert_not log.valid?
  end

  test "duration_seconds — started_at/completed_at 없으면 nil" do
    log = EcountSyncLog.new(sync_type: "products")
    assert_nil log.duration_seconds
  end

  test "duration_seconds — 경과 시간 계산" do
    now = Time.current
    log = EcountSyncLog.new(sync_type: "products", started_at: now, completed_at: now + 5.seconds)
    assert_equal 5.0, log.duration_seconds
  end

  test "recent scope — scope 호출 가능" do
    assert_respond_to EcountSyncLog, :recent
    assert_nothing_raised { EcountSyncLog.recent.to_sql }
  end

  test "failed_today scope — scope 호출 가능" do
    assert_respond_to EcountSyncLog, :failed_today
    assert_nothing_raised { EcountSyncLog.failed_today.to_sql }
  end
end
