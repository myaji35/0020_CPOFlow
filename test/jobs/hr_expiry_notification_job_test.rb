# frozen_string_literal: true

require "test_helper"

class HrExpiryNotificationJobTest < ActiveJob::TestCase
  test "VISA_TRIGGER_DAYS 상수 정의됨" do
    assert_equal [ 60, 30, 14 ], HrExpiryNotificationJob::VISA_TRIGGER_DAYS
  end

  test "CONTRACT_TRIGGER_DAYS 상수 정의됨" do
    assert_equal [ 30, 14 ], HrExpiryNotificationJob::CONTRACT_TRIGGER_DAYS
  end

  test "perform — 에러 없이 실행됨" do
    assert_nothing_raised { HrExpiryNotificationJob.perform_now }
  end

  test "job queue" do
    assert_equal "default", HrExpiryNotificationJob.new.queue_name
  end
end
