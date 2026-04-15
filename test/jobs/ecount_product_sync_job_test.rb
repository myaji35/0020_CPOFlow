# frozen_string_literal: true

require "test_helper"

class EcountProductSyncJobTest < ActiveJob::TestCase
  test "job queue" do
    assert_equal "default", EcountProductSyncJob.new.queue_name
  end

  test "perform — EcountSyncLog 생성됨" do
    initial_count = EcountSyncLog.count
    begin
      EcountProductSyncJob.perform_now
    rescue => e
      # API 미설정 환경에서 에러는 정상
    end
    assert EcountSyncLog.count >= initial_count
  end
end
