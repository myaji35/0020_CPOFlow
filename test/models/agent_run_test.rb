# frozen_string_literal: true

require "test_helper"

class AgentRunTest < ActiveSupport::TestCase
  test "track returns the block result and finishes successfully" do
    result = AgentRun.track(agent: "test.agent") { :result }

    assert_equal :result, result
    run = AgentRun.last
    assert_equal "success", run.status
    assert_operator run.duration_ms, :>=, 0
  end

  test "track records and reraises the original exception" do
    error = assert_raises(ArgumentError) do
      AgentRun.track(agent: "test.agent") { raise ArgumentError, "bad input" }
    end

    assert_equal "bad input", error.message
    run = AgentRun.last
    assert_equal "failure", run.status
    assert_includes run.error_message, "ArgumentError"
  end

  test "track tolerates a failure to create the run" do
    original_create = AgentRun.method(:create!)
    AgentRun.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "boom" }

    result = AgentRun.track(agent: "test.agent") { :still_runs }

    assert_equal :still_runs, result
  ensure
    AgentRun.define_singleton_method(:create!, original_create)
  end

  test "note values are persisted by finish and meta is truncated" do
    run = AgentRun.start!(agent: "test.agent", kind: "service", order: nil, parent: nil, source: nil)
    run.note(model: "haiku-4.5", cost_usd: 0.001234, input_tokens: 10,
             output_tokens: 20, cache_read_tokens: 5, meta: { data: "x" * 5000 })
    run.finish!
    run.reload

    assert_equal "haiku-4.5", run.model
    assert_equal 0.001234.to_d, run.cost_usd
    assert_equal 10, run.input_tokens
    assert_equal 20, run.output_tokens
    assert_equal 5, run.cache_read_tokens
    assert_equal 4096, run.meta.length
  end

  test "null run accepts all recording methods" do
    run = AgentRun::NullRun.new

    assert_same run, run.note(model: "ignored")
    assert_same run, run.finish!(status: "success")
    assert_same run, run.fail!(RuntimeError.new("ignored"))
    refute run.persisted?
  end
end
