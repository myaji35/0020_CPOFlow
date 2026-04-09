# frozen_string_literal: true

require "test_helper"

class Gmail::SonnetEscalatorServiceTest < ActiveSupport::TestCase
  def email
    {
      subject: "Inquiry about concrete admixture",
      from:    "buyer@unknown.com",
      body:    "We may need some concrete waterproofing for our project."
    }
  end

  def haiku_medium
    Gmail::ClassificationResult.new(
      verdict: :confirmed, is_rfq: true, confidence: "medium",
      stage_reached: 2, classifier_version: "v2",
      reason: "weak signal", extracted: { customer_name: "ACME" },
      cost_usd: 0.0013, latency_ms: 450, cache_hit: false,
      model: "haiku-4.5"
    )
  end

  def haiku_low
    haiku_medium.with(confidence: "low")
  end

  # ===== API 성공 케이스 =====
  test "escalate: API 성공 → Sonnet 결과 채택" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "confirmed", is_rfq: true, confidence: "high")

    assert_equal :confirmed, result.verdict
    assert result.is_rfq
    assert_equal "high", result.confidence
    assert_equal 3, result.stage_reached
    assert_equal "v2", result.classifier_version
    assert_equal "sonnet-4.5", result.model
  end

  test "escalate: Sonnet excluded 판정" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "excluded", is_rfq: false, confidence: "high")

    assert_equal :excluded, result.verdict
    refute result.is_rfq
  end

  test "escalate: Sonnet이 override_reason 을 reason 에 저장" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "confirmed", is_rfq: true, confidence: "high",
                          override_reason: "Haiku missed the BOQ attachment reference")
    assert_includes result.reason, "BOQ"
  end

  test "escalate: extracted 필드 전달" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "confirmed", is_rfq: true, confidence: "high",
                          extracted: { "customer_name" => "KEPCO", "items" => [ "Sika 101" ] })
    assert_equal "KEPCO", result.extracted["customer_name"]
    assert_equal [ "Sika 101" ], result.extracted["items"]
  end

  # ===== Fallback 케이스 =====
  test "escalate: API 에러 → Haiku 결과 채택 (fallback)" do
    result = run_escalate(haiku_medium, stub_kind: :error, error: StandardError.new("timeout"))

    assert_equal 3, result.stage_reached
    assert_equal "haiku-4.5-fallback", result.model
    assert_includes result.reason, "stage3_fallback_to_stage2"
    assert_equal :confirmed, result.verdict
    assert_equal "medium", result.confidence
  end

  test "escalate: API nil 응답 → Haiku fallback" do
    result = run_escalate(haiku_medium, stub_kind: :nil)
    assert_equal "haiku-4.5-fallback", result.model
    assert_includes result.reason, "api_returned_nil"
  end

  test "escalate: JSON parse 실패 → Haiku fallback" do
    result = run_escalate(haiku_medium, stub_kind: :raw_text, text: "not a json at all")
    assert_equal "haiku-4.5-fallback", result.model
    assert_includes result.reason, "parse_failed"
  end

  test "escalate: Haiku 결과도 nil → safe_confirmed_fallback (Recall 우선)" do
    result = run_escalate(nil, stub_kind: :error, error: StandardError.new("network"))
    assert_equal :confirmed, result.verdict
    assert_equal "rule-only-fallback", result.model
    assert_includes result.reason, "stage3_total_failure"
  end

  # ===== 비용 계산 =====
  test "compute_cost: cache_read_input_tokens 90% 할인 반영" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "confirmed", is_rfq: true, confidence: "high",
                          usage: { input_tokens: 500, output_tokens: 100, cache_read_input_tokens: 3000 })
    # input_fresh=500 * $3/1M = $0.0015
    # input_cached=3000 * $3/1M * 0.1 = $0.0009 (90% 할인)
    # output=100 * $15/1M = $0.0015
    # total ≈ $0.0039
    assert_in_delta 0.0039, result.cost_usd, 0.0005
    assert result.cache_hit
  end

  test "compute_cost: cache_read = 0 이면 cache_hit false" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "confirmed", is_rfq: true, confidence: "high",
                          usage: { input_tokens: 500, output_tokens: 100, cache_read_input_tokens: 0 })
    refute result.cache_hit
  end

  # ===== Recall 우선 보장 =====
  test "escalate: 알 수 없는 verdict 문자열 → confirmed 처리 (Recall 우선)" do
    result = run_escalate(haiku_medium, stub_kind: :response,
                          verdict: "maybe", is_rfq: true, confidence: "low")
    assert_equal :confirmed, result.verdict
  end

  test "escalate: stage_reached 항상 3" do
    r1 = run_escalate(haiku_medium, stub_kind: :response,
                      verdict: "confirmed", is_rfq: true, confidence: "high")
    assert_equal 3, r1.stage_reached

    r2 = run_escalate(haiku_low, stub_kind: :error, error: StandardError.new("x"))
    assert_equal 3, r2.stage_reached
  end

  # ===== Haiku Hash 호환성 (v1 interop) =====
  test "escalate: Haiku가 Hash 형태여도 fallback 동작" do
    haiku_hash = {
      verdict: :confirmed, confidence: "medium",
      reason: "from hash", is_rfq: true, extracted: {}
    }
    result = run_escalate(haiku_hash, stub_kind: :error, error: StandardError.new("x"))

    assert_equal "haiku-4.5-fallback", result.model
    assert_equal "medium", result.confidence
    assert_includes result.reason, "stage3_fallback_to_stage2"
  end

  # ===== 스텁 헬퍼 =====
  # Mocha 미사용 → singleton_method override 방식으로 인스턴스 레벨 스텁
  private

  def build_service(haiku)
    svc = Gmail::SonnetEscalatorService.new(email, haiku)
    @current_svc = svc
    svc
  end

  # svc 인스턴스 반환하지 않고, 테스트에서 new → stub → escalate 을 한 줄로 하기 위해
  # escalate 호출 대신 "stub 먼저 + new + escalate" 순서를 간단화한 헬퍼
  def run_escalate(haiku, stub_kind:, **opts)
    svc = Gmail::SonnetEscalatorService.new(email, haiku)

    case stub_kind
    when :response
      mock = build_mock_response(**opts)
      svc.define_singleton_method(:call_sonnet_api) { mock }
    when :nil
      svc.define_singleton_method(:call_sonnet_api) { nil }
    when :error
      err = opts[:error] || StandardError.new("stub error")
      svc.define_singleton_method(:call_sonnet_api) { raise err }
    when :raw_text
      text = opts[:text]
      mock = Object.new
      mock.define_singleton_method(:content) { [ OpenStruct.new(text: text) ] }
      mock.define_singleton_method(:usage) { nil }
      svc.define_singleton_method(:call_sonnet_api) { mock }
    end

    svc.escalate
  end

  def build_mock_response(verdict:, is_rfq:, confidence:, override_reason: "test reason",
                            extracted: {}, usage: nil)
    payload = {
      "final_verdict"    => verdict,
      "is_rfq"           => is_rfq,
      "sonnet_confidence" => confidence,
      "override_reason"  => override_reason,
      "extracted"        => extracted
    }
    mock = Object.new
    mock.define_singleton_method(:content) { [ OpenStruct.new(text: payload.to_json) ] }
    if usage
      u = OpenStruct.new(
        input_tokens:            usage[:input_tokens],
        output_tokens:           usage[:output_tokens],
        cache_read_input_tokens: usage[:cache_read_input_tokens]
      )
      mock.define_singleton_method(:usage) { u }
    else
      mock.define_singleton_method(:usage) { nil }
    end
    mock
  end
end
