# frozen_string_literal: true

require "test_helper"

class CardStatusAutoAssignJobTest < ActiveJob::TestCase
  test "perform — 에러 없이 실행됨" do
    assert_nothing_raised { CardStatusAutoAssignJob.perform_now }
  end

  test "job queue" do
    assert_equal "default", CardStatusAutoAssignJob.new.queue_name
  end
end
