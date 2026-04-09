# frozen_string_literal: true

require "test_helper"

# ISS-057 — ClassifyV2Day3Gate 단위 테스트
#
# 6개 시나리오:
#   1. passed — 모든 임계값 이내
#   2. fail — daily_cost 초과
#   3. fail — sonnet_escalation 비율 초과
#   4. fail — safety_fallback 비율 초과
#   5. fail — v1(user 액션) ↔ v2 불일치 초과
#   6. neutral — 빈 데이터 (모든 임계값 passed)
class ClassifyV2Day3GateTest < ActiveSupport::TestCase
  TEST_PREFIX = "day3gate_test_"

  setup do
    ClassificationLog.where("email_message_id LIKE ?", "#{TEST_PREFIX}%").destroy_all
    Order.where("source_email_id LIKE ?", "#{TEST_PREFIX}%").destroy_all
  end

  teardown do
    ClassificationLog.where("email_message_id LIKE ?", "#{TEST_PREFIX}%").destroy_all
    Order.where("source_email_id LIKE ?", "#{TEST_PREFIX}%").destroy_all
  end

  # --- 1. passed -----------------------------------------------------------
  test "passed — 모든 임계값 이내" do
    # 100건: stage1=50, stage2=40, stage3=10 (sonnet 10%)
    # cost: 100 × 0.001 = 0.10 / 3일 = 0.033 (< 0.35)
    100.times do |i|
      stage = i < 50 ? 1 : (i < 90 ? 2 : 3)
      create_log(suffix: "ok_#{i}", stage: stage, cost: 0.001, reason: "stage#{stage}")
    end
    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "passed", result[:status], "expected passed, got: #{result[:failures].inspect}"
    assert_empty result[:failures]
  end

  # --- 2. daily_cost 초과 --------------------------------------------------
  test "fail — daily_cost 초과" do
    # 5건 × $0.30 = $1.50 / 3일 ≈ $0.50 > $0.35
    5.times do |i|
      create_log(suffix: "cost_#{i}", stage: 2, cost: 0.30, reason: "stage2_haiku")
    end
    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "failed", result[:status]
    assert result[:failures].any? { |f| f[:name] == "daily_cost_usd" },
           "expected daily_cost_usd failure, got: #{result[:failures].map { |f| f[:name] }}"
  end

  # --- 3. sonnet_ratio 초과 ------------------------------------------------
  test "fail — sonnet_escalation_ratio 초과" do
    # 10건 전부 stage 3 (Sonnet 100%)
    10.times do |i|
      create_log(suffix: "sonnet_#{i}", stage: 3, cost: 0.001, reason: "stage3", model: "sonnet-4.5")
    end
    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "failed", result[:status]
    assert result[:failures].any? { |f| f[:name] == "sonnet_escalation_ratio" }
  end

  # --- 4. safety_fallback 초과 ---------------------------------------------
  test "fail — safety_fallback_ratio 초과" do
    # 10건 전부 safety_fallback (100%)
    10.times do |i|
      create_log(
        suffix: "fb_#{i}", stage: 0, cost: 0.0,
        reason: "safety_fallback:Net::ReadTimeout",
        model: "rule-only", verdict: "uncertain"
      )
    end
    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "failed", result[:status]
    assert result[:failures].any? { |f| f[:name] == "safety_fallback_ratio" }
  end

  # --- 5. v1 ↔ v2 불일치 --------------------------------------------------
  test "fail — v1_v2_disagreement_ratio 초과" do
    user = test_user
    orders = []
    10.times do |i|
      order = Order.create!(
        title:           "day3gate disagreement #{i}",
        customer_name:   "TestCustomer",
        status:          :new_rfq,
        rfq_status:      :rfq_triage, # 사용자는 confirmed 처리
        user:            user,
        source_email_id: "#{TEST_PREFIX}da_#{i}"
      )
      orders << order

      # v2는 excluded 판정 → 전원 불일치 (100%)
      ClassificationLog.create!(
        order_id:           order.id,
        email_message_id:   "#{TEST_PREFIX}da_#{i}",
        classifier_version: "v2",
        stage_reached:      2,
        verdict:            "excluded",
        is_rfq:             false,
        confidence:         0.4,
        would_exclude:      true,
        reason:             "stage2_haiku",
        cost_usd:           0.001,
        latency_ms:         100,
        cache_hit:          false,
        model:              "haiku-4.5",
        created_at:         1.day.ago
      )
    end

    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "failed", result[:status]
    assert result[:failures].any? { |f| f[:name] == "v1_v2_disagreement_ratio" },
           "expected v1_v2 failure, got: #{result[:failures].map { |f| f[:name] }}"
    # Order destroy는 teardown에서 처리 (log 선삭제 후 Order 삭제 순서).
  end

  # --- 6. neutral (빈 데이터) ----------------------------------------------
  test "neutral — 빈 데이터는 passed" do
    result = ClassifyV2Day3Gate.new(window_days: 3).run
    assert_equal "passed", result[:status]
  end

  private

  def create_log(suffix:, stage:, cost:, reason:, model: "haiku-4.5", verdict: "confirmed")
    ClassificationLog.create!(
      email_message_id:   "#{TEST_PREFIX}#{suffix}",
      classifier_version: "v2",
      stage_reached:      stage,
      verdict:            verdict,
      is_rfq:             verdict == "confirmed",
      confidence:         0.9,
      would_exclude:      false,
      reason:             reason,
      cost_usd:           cost,
      latency_ms:         100,
      cache_hit:          false,
      model:              model,
      created_at:         1.day.ago
    )
  end

  def test_user
    User.find_by(email: "day3gate@test.local") || User.create!(
      email:                 "day3gate@test.local",
      password:              "password123",
      password_confirmation: "password123",
      name:                  "Day3Gate Test"
    )
  end
end
