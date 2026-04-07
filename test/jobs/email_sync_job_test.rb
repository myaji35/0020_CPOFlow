# frozen_string_literal: true

require "test_helper"

class EmailSyncJobTest < ActiveJob::TestCase
  test "perform_later enqueue 가능" do
    assert_enqueued_with(job: EmailSyncJob) do
      EmailSyncJob.perform_later
    end
  end

  test "perform_later — account_id 파라미터로 enqueue" do
    assert_enqueued_with(job: EmailSyncJob) do
      EmailSyncJob.perform_later(account_id: 9999)
    end
  end
end
