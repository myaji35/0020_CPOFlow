# frozen_string_literal: true

require "test_helper"

class Gmail::ClassificationResultTest < ActiveSupport::TestCase
  def build(opts = {})
    Gmail::ClassificationResult.new(
      verdict: :confirmed, is_rfq: true, confidence: "high",
      stage_reached: 2, classifier_version: "v2",
      reason: "test", extracted: {},
      cost_usd: 0.001, latency_ms: 100, cache_hit: false,
      model: "haiku-4.5"
    ).with(**opts)
  end

  test "confirmed_by_haiku? — Stage 2 high confidence" do
    assert build(stage_reached: 2, confidence: "high", verdict: :confirmed).confirmed_by_haiku?
  end

  test "confirmed_by_haiku? false — Stage 2 medium" do
    refute build(stage_reached: 2, confidence: "medium").confirmed_by_haiku?
  end

  test "confirmed_by_haiku? false — Stage 3" do
    refute build(stage_reached: 3, confidence: "high").confirmed_by_haiku?
  end

  test "escalate_to_sonnet? true — Stage 2 medium" do
    assert build(stage_reached: 2, confidence: "medium").escalate_to_sonnet?
  end

  test "escalate_to_sonnet? true — Stage 2 low" do
    assert build(stage_reached: 2, confidence: "low").escalate_to_sonnet?
  end

  test "escalate_to_sonnet? false — Stage 2 high" do
    refute build(stage_reached: 2, confidence: "high").escalate_to_sonnet?
  end

  test "escalate_to_sonnet? false — Stage 1 or 3" do
    refute build(stage_reached: 1).escalate_to_sonnet?
    refute build(stage_reached: 3).escalate_to_sonnet?
  end

  test "safe_for_cutover? — confirmed or excluded" do
    assert build(verdict: :confirmed).safe_for_cutover?
    assert build(verdict: :excluded).safe_for_cutover?
    refute build(verdict: :uncertain).safe_for_cutover?
  end

  test "to_log_hash — 필수 필드 포함" do
    h = build.to_log_hash
    assert_equal "confirmed", h[:verdict]
    assert_equal "high", h[:confidence]
    assert_equal 2, h[:stage_reached]
    assert_equal "v2", h[:classifier_version]
    assert_equal "haiku-4.5", h[:model]
  end

  test "to_log_hash — reason 500자 제한" do
    long = "x" * 1000
    h = build(reason: long).to_log_hash
    assert_equal 500, h[:reason].length
  end
end
