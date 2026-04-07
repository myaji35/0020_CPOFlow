# frozen_string_literal: true

require "test_helper"

class AgentInsightJobTest < ActiveJob::TestCase
  test "perform_later enqueue 가능" do
    assert_enqueued_with(job: AgentInsightJob) do
      AgentInsightJob.perform_later(999999)
    end
  end

  test "perform — 존재하지 않는 order_id는 조용히 반환" do
    assert_nothing_raised do
      AgentInsightJob.new.perform(999999)
    end
  end
end
