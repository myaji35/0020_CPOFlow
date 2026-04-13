# frozen_string_literal: true

require "test_helper"

class Gmail::ClassificationOrchestratorTest < ActiveSupport::TestCase
  # ===== 공통 헬퍼 =====
  def build_email(from:, subject: "Need pricing", body: "Please send pricing info.", message_id: nil)
    {
      message_id: message_id || "msg-#{SecureRandom.hex(4)}",
      from: from,
      subject: subject,
      body: body
    }
  end

  # Haiku analyze를 class-level 스텁으로 override. block 안에서만 적용, ensure로 복구.
  def with_haiku_stub(return_hash)
    klass = Gmail::LlmRfqAnalyzerService
    klass.class_eval do
      alias_method :__orig_analyze, :analyze
      define_method(:analyze) { return_hash }
    end
    yield
  ensure
    klass.class_eval do
      remove_method :analyze
      alias_method :analyze, :__orig_analyze
      remove_method :__orig_analyze
    end
  end

  def with_sonnet_stub(return_result_or_block)
    klass = Gmail::SonnetEscalatorService
    klass.class_eval do
      alias_method :__orig_escalate, :escalate
      if return_result_or_block.is_a?(Proc)
        define_method(:escalate, &return_result_or_block)
      else
        define_method(:escalate) { return_result_or_block }
      end
    end
    yield
  ensure
    klass.class_eval do
      remove_method :escalate
      alias_method :escalate, :__orig_escalate
      remove_method :__orig_escalate
    end
  end

  # Haiku가 호출되면 raise 하는 스텁 (stage0/1에서 조기 종료 검증용)
  def with_haiku_forbidden
    klass = Gmail::LlmRfqAnalyzerService
    klass.class_eval do
      alias_method :__orig_analyze, :analyze
      define_method(:analyze) { raise "Haiku가 호출되어서는 안 된다 (stage0/1 early-exit 위반)" }
    end
    yield
  ensure
    klass.class_eval do
      remove_method :analyze
      alias_method :analyze, :__orig_analyze
      remove_method :__orig_analyze
    end
  end

  def with_sonnet_forbidden
    klass = Gmail::SonnetEscalatorService
    klass.class_eval do
      alias_method :__orig_escalate, :escalate
      define_method(:escalate) { raise "Sonnet이 호출되어서는 안 된다" }
    end
    yield
  ensure
    klass.class_eval do
      remove_method :escalate
      alias_method :escalate, :__orig_escalate
      remove_method :__orig_escalate
    end
  end

  # ===== 1. Stage 0: Ariba sender → confirmed =====
  test "stage0_ariba_sender: ariba.com 발신자면 즉시 confirmed" do
    email = build_email(
      from: "events@ariba.com",
      subject: "ADNOC has invited you to participate",
      body: "sourcing event 1234567890"
    )
    before_count = ClassificationLog.count

    result = with_haiku_forbidden { Gmail::ClassificationOrchestrator.new(email).classify }

    assert_equal :confirmed, result.verdict
    assert_equal 0, result.stage_reached
    assert_equal "v2", result.classifier_version
    assert_equal "stage0_ariba_sender", result.reason
    assert_equal "rule-only", result.model
    assert_equal before_count + 1, ClassificationLog.count
  end

  # ===== 2. Stage 0: Own sender → excluded =====
  test "stage0_own_sender: atoz2010.com 발신자면 즉시 excluded" do
    email = build_email(from: "sales@atoz2010.com", subject: "Internal update")
    before_count = ClassificationLog.count

    result = with_haiku_forbidden { Gmail::ClassificationOrchestrator.new(email).classify }

    assert_equal :excluded, result.verdict
    assert_equal 0, result.stage_reached
    assert_equal "stage0_own_sender", result.reason
    assert_equal before_count + 1, ClassificationLog.count
  end

  # ===== 3. Stage 0: Excluded sender pattern → excluded =====
  test "stage0_excluded_sender: noreply.github.com 발신자면 즉시 excluded" do
    email = build_email(from: "bot@noreply.github.com", subject: "[GitHub] PR merged")

    result = with_haiku_forbidden { Gmail::ClassificationOrchestrator.new(email).classify }

    assert_equal :excluded, result.verdict
    assert_equal 0, result.stage_reached
    assert_equal "stage0_excluded_pattern", result.reason
  end

  # ===== 4. Stage 1: reject_no_signal → uncertain (recall 우선 정책) =====
  test "stage1_reject_no_signal: 일반 도메인 + RFQ 신호 0개 → uncertain at stage 1 (recall 우선)" do
    email = build_email(
      from: "friend@example-unknown.com",
      subject: "Lunch tomorrow",
      body: "Hey are you free for lunch tomorrow at the usual place"
    )
    before_count = ClassificationLog.count

    result = with_haiku_forbidden { Gmail::ClassificationOrchestrator.new(email).classify }

    assert_equal :uncertain, result.verdict,
      "Recall 우선 정책: 신호 없는 메일도 uncertain으로 수신"
    assert_equal 1, result.stage_reached
    assert_match(/stage1_no_signal_but_recall_priority/, result.reason)
    assert_equal before_count + 1, ClassificationLog.count
  end

  # ===== 5. Stage 2: Haiku high confidence confirmed → 확정 =====
  test "stage2_haiku_high_confirmed: Haiku high 면 Stage 2에서 확정 (Sonnet 호출 X)" do
    email = build_email(
      from: "buyer@randomcorp.com",
      subject: "Please send RFQ for Sika products",
      body: "We need 100 kg MonoTop 107 Seal urgently."
    )

    haiku_hash = {
      is_rfq: true,
      confidence: "high",
      reason: "strong RFQ signal + product match",
      customer_name: "RandomCorp",
      items: ["Sika MonoTop 107"],
      quantities: ["100 kg"],
      urgency: "urgent"
    }

    result = with_haiku_stub(haiku_hash) do
      with_sonnet_forbidden do
        Gmail::ClassificationOrchestrator.new(email).classify
      end
    end

    assert_equal :confirmed, result.verdict
    assert_equal 2, result.stage_reached
    assert_equal "high", result.confidence
    assert_equal "haiku-4.5", result.model
    assert_equal "RandomCorp", result.extracted[:customer_name]
  end

  # ===== 6. Stage 3: Haiku medium → Sonnet escalated confirmed =====
  test "stage3_escalated_confirmed: Haiku medium → Sonnet 승격 후 confirmed" do
    email = build_email(
      from: "procurement@unknowncorp.com",
      subject: "Pricing request for Sika",
      body: "Please provide quote for concrete epoxy sealant 200 kg."
    )

    haiku_hash = {
      is_rfq: true,
      confidence: "medium",
      reason: "weak signal, needs escalation"
    }

    sonnet_result = Gmail::ClassificationResult.new(
      verdict: :confirmed, is_rfq: true, confidence: "high",
      stage_reached: 3, classifier_version: "v2",
      reason: "sonnet override: clear RFQ context",
      extracted: { "customer_name" => "UnknownCorp" },
      cost_usd: 0.0039, latency_ms: 820, cache_hit: true,
      model: "sonnet-4.5"
    )

    result = with_haiku_stub(haiku_hash) do
      with_sonnet_stub(sonnet_result) do
        Gmail::ClassificationOrchestrator.new(email).classify
      end
    end

    assert_equal :confirmed, result.verdict
    assert_equal 3, result.stage_reached
    assert_equal "sonnet-4.5", result.model
    assert_match(/sonnet override/, result.reason)
  end

  # ===== 7. Stage 3 fallback: Sonnet이 내부 rescue로 haiku fallback 반환 =====
  test "stage3_fallback_to_haiku: Sonnet이 fallback result 반환 시 orchestrator가 그대로 로깅" do
    email = build_email(
      from: "buyer@somewhere.com",
      subject: "quote for waterproofing",
      body: "need waterproofing admixture urgently."
    )

    haiku_hash = { is_rfq: true, confidence: "medium", reason: "weak signal" }

    fallback_result = Gmail::ClassificationResult.new(
      verdict: :confirmed, is_rfq: true, confidence: "medium",
      stage_reached: 3, classifier_version: "v2",
      reason: "stage3_fallback_to_stage2: exception:Net::ReadTimeout",
      extracted: {},
      cost_usd: 0.0, latency_ms: 0, cache_hit: false,
      model: "haiku-4.5-fallback"
    )

    result = with_haiku_stub(haiku_hash) do
      with_sonnet_stub(fallback_result) do
        Gmail::ClassificationOrchestrator.new(email).classify
      end
    end

    assert_equal 3, result.stage_reached
    assert_equal "haiku-4.5-fallback", result.model
    assert_match(/stage3_fallback_to_stage2/, result.reason)
  end

  # ===== 8. ClassificationLog insert 확인 =====
  test "classification_log_inserted: classifier_version v2, email_message_id, stage 기록" do
    email = build_email(from: "user@atoz2010.com", subject: "Internal", message_id: "msg-log-test-001")
    before = ClassificationLog.count

    orchestrator = Gmail::ClassificationOrchestrator.new(email)
    with_haiku_forbidden { orchestrator.classify }

    assert_equal before + 1, ClassificationLog.count
    log = ClassificationLog.order(:id).last
    assert_equal "v2", log.classifier_version
    assert_equal "msg-log-test-001", log.email_message_id
    assert_equal 0, log.stage_reached
    assert_equal "excluded", log.verdict
    assert_equal "rule-only", log.model
    assert_equal false, log.would_exclude
    assert log.confidence.present?

    # ISS-056: last_log_id가 방금 insert된 row의 ID와 일치해야 함
    assert_not_nil orchestrator.last_log_id
    assert_equal log.id, orchestrator.last_log_id
  end

  # ===== 9. ISS-056: 재시도 시 2회 호출 시 서로 다른 last_log_id =====
  test "iss056_retry_each_call_has_distinct_last_log_id" do
    email = build_email(from: "user@atoz2010.com", subject: "Dup", message_id: "msg-iss056-dup")

    orch1 = Gmail::ClassificationOrchestrator.new(email)
    with_haiku_forbidden { orch1.classify }
    orch2 = Gmail::ClassificationOrchestrator.new(email)
    with_haiku_forbidden { orch2.classify }

    assert_not_nil orch1.last_log_id
    assert_not_nil orch2.last_log_id
    assert_not_equal orch1.last_log_id, orch2.last_log_id,
      "각 classify 호출은 독립된 ClassificationLog row를 캡처해야 함"
    # 동일 email_message_id로 2개 row 존재
    assert_equal 2, ClassificationLog.where(email_message_id: "msg-iss056-dup").count
  end
end
