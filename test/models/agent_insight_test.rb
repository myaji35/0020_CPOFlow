require "test_helper"

class AgentInsightTest < ActiveSupport::TestCase
  test "insight_type 없으면 invalid" do
    insight = AgentInsight.new(title: "Test")
    assert_not insight.valid?
    assert insight.errors[:insight_type].any?
  end

  test "title 없으면 invalid" do
    insight = AgentInsight.new(insight_type: "price_comparison")
    assert_not insight.valid?
    assert insight.errors[:title].any?
  end

  test "severity enum 유효" do
    %w[info warning alert].each do |s|
      assert AgentInsight.severities.key?(s), "severity #{s} 누락"
    end
  end

  test "insight_type enum 유효" do
    %w[price_comparison supplier_risk due_date_risk cost_saving].each do |t|
      assert AgentInsight.insight_types.key?(t), "insight_type #{t} 누락"
    end
  end

  test "active scope 동작" do
    assert_nothing_raised { AgentInsight.active.count }
  end

  test "for_dashboard scope 동작" do
    assert_nothing_raised { AgentInsight.for_dashboard.count }
  end

  test "for_order scope 동작" do
    assert_nothing_raised { AgentInsight.for_order(0).count }
  end

  test "associations 쿼리 정상" do
    assert_nothing_raised do
      AgentInsight.includes(:order, :supplier).limit(5).to_a
    end
  end
end
