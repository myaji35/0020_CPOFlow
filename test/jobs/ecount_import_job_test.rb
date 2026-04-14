# frozen_string_literal: true

require "test_helper"

class EcountImportJobTest < ActiveJob::TestCase
  test "perform — RecordNotFound 시 discard (에러 없음)" do
    assert_nothing_raised { EcountImportJob.perform_now(0) }
  end

  test "job queue" do
    assert_equal "default", EcountImportJob.new.queue_name
  end
end
