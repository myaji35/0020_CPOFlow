# frozen_string_literal: true

require "test_helper"

class SheetsSyncJobTest < ActiveJob::TestCase
  test "perform — mock 모드에서 에러 없이 실행됨" do
    # credentials 미설정 → SheetsService mock_mode → 에러 없이 실행
    assert_nothing_raised { SheetsSyncJob.perform_now }
  end

  test "job queue" do
    assert_equal "default", SheetsSyncJob.new.queue_name
  end
end
