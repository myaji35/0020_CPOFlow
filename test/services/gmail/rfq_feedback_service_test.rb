# frozen_string_literal: true

require "test_helper"

class Gmail::RfqFeedbackServiceTest < ActiveSupport::TestCase
  test "few_shot_examples — 배열 반환" do
    examples = Gmail::RfqFeedbackService.few_shot_examples(limit: 5)
    assert examples.is_a?(Array)
    assert examples.length <= 5
  end

  test "few_shot_examples — 각 항목에 subject, verdict 포함" do
    examples = Gmail::RfqFeedbackService.few_shot_examples(limit: 3)
    examples.each do |ex|
      assert ex.key?(:subject), "subject 키 없음: #{ex.inspect}"
      assert ex.key?(:verdict), "verdict 키 없음: #{ex.inspect}"
    end
  end

  test "score_from_confidence — high → 0.9" do
    score = Gmail::RfqFeedbackService.score_from_confidence("high")
    assert_in_delta 0.9, score, 0.05
  end

  test "score_from_confidence — medium → 0.6~0.7" do
    score = Gmail::RfqFeedbackService.score_from_confidence("medium")
    assert score >= 0.5 && score <= 0.8
  end

  test "score_from_confidence — low → 0.3~0.4" do
    score = Gmail::RfqFeedbackService.score_from_confidence("low")
    assert score <= 0.5
  end

  test "accuracy_stats — 결과 Hash에 total_feedback 포함" do
    stats = Gmail::RfqFeedbackService.accuracy_stats(window_days: 7)
    assert stats.is_a?(Hash)
    assert stats.key?(:total)
  end

  test "domain_history — 결과 Hash 반환" do
    result = Gmail::RfqFeedbackService.domain_history("example.com")
    assert result.is_a?(Hash)
  end
end
