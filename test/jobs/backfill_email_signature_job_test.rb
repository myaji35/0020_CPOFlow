# frozen_string_literal: true

require "test_helper"

class BackfillEmailSignatureJobTest < ActiveJob::TestCase
  test "perform — 에러 없이 실행됨" do
    assert_nothing_raised { BackfillEmailSignatureJob.perform_now(batch_size: 1) }
  end

  test "job queue" do
    assert_equal "default", BackfillEmailSignatureJob.new.queue_name
  end
end
