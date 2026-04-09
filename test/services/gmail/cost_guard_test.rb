require "test_helper"

class Gmail::CostGuardTest < ActiveSupport::TestCase
  setup do
    ClassificationLog.where("email_message_id LIKE ?", "cg_test%").destroy_all
    Rails.cache.delete(Gmail::CostGuard::WARN_LOG_CACHE_KEY)
  end

  teardown do
    ClassificationLog.where("email_message_id LIKE ?", "cg_test%").destroy_all
  end

  test "today_cost — 오늘 로그만 합산 (어제 로그 제외)" do
    ClassificationLog.create!(
      email_message_id: "cg_test_today",
      classifier_version: "v2", stage_reached: 2, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 0.10, latency_ms: 100, cache_hit: false, model: "haiku-4.5",
      created_at: Time.current.beginning_of_day + 1.hour
    )
    ClassificationLog.create!(
      email_message_id: "cg_test_yesterday",
      classifier_version: "v2", stage_reached: 2, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 1.00, latency_ms: 100, cache_hit: false, model: "haiku-4.5",
      created_at: 1.day.ago
    )
    assert_in_delta 0.10, Gmail::CostGuard.today_cost, 0.0001
  end

  test "exceeded? false — 예산 이내" do
    ClassificationLog.create!(
      email_message_id: "cg_test_within",
      classifier_version: "v2", stage_reached: 2, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 0.10, latency_ms: 100, cache_hit: false, model: "haiku-4.5",
      created_at: Time.current.beginning_of_day + 1.hour
    )
    assert_not Gmail::CostGuard.exceeded?
  end

  test "exceeded? true — 예산 초과" do
    ClassificationLog.create!(
      email_message_id: "cg_test_over",
      classifier_version: "v2", stage_reached: 3, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 0.50, latency_ms: 500, cache_hit: false, model: "sonnet-4.5",
      created_at: Time.current.beginning_of_day + 1.hour
    )
    assert Gmail::CostGuard.exceeded?
  end

  test "status — utilization_pct 계산" do
    ClassificationLog.create!(
      email_message_id: "cg_test_status",
      classifier_version: "v2", stage_reached: 2, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 0.175, latency_ms: 100, cache_hit: false, model: "haiku-4.5",
      created_at: Time.current.beginning_of_day + 1.hour
    )
    status = Gmail::CostGuard.status
    assert_in_delta 0.175, status[:today_cost], 0.0001
    assert_equal 0.35,     status[:budget]
    assert_not status[:exceeded]
    assert_in_delta 50.0,  status[:utilization_pct], 0.1
  end

  test "warn_once! — 하루에 1회만 로그" do
    ClassificationLog.create!(
      email_message_id: "cg_test_warn",
      classifier_version: "v2", stage_reached: 3, verdict: "confirmed",
      is_rfq: true, confidence: 0.9, would_exclude: false, reason: "x",
      cost_usd: 1.0, latency_ms: 500, cache_hit: false, model: "sonnet-4.5",
      created_at: Time.current.beginning_of_day + 1.hour
    )

    # test 환경 기본 Rails.cache = NullStore → MemoryStore 로 일시 교체
    original_cache = Rails.cache
    Rails.instance_variable_set(:@cache, ActiveSupport::Cache::MemoryStore.new)
    Rails.cache.delete(Gmail::CostGuard::WARN_LOG_CACHE_KEY)

    original_logger = Rails.logger
    warn_count = 0
    fake = Object.new
    fake.define_singleton_method(:warn) { |_msg| warn_count += 1 }
    fake.define_singleton_method(:info) { |_msg| }
    fake.define_singleton_method(:error){ |_msg| }
    fake.define_singleton_method(:debug){ |_msg| }
    Rails.logger = fake

    Gmail::CostGuard.warn_once!
    Gmail::CostGuard.warn_once!
    Gmail::CostGuard.warn_once!
    assert_equal 1, warn_count
  ensure
    Rails.logger = original_logger if defined?(original_logger) && original_logger
    Rails.instance_variable_set(:@cache, original_cache) if defined?(original_cache) && original_cache
  end
end
