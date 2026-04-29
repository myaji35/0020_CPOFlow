# frozen_string_literal: true

require "test_helper"

# ISS-055 완전한 Shadow Mode 옵션 B (대표님 지시):
#   - 모든 v2 verdict → rfq_pending (v2는 메트릭/로그에만 남고 상태 전이 없음)
#   - 사용자가 Inbox UI에서 명시적으로 "칸반 적용" 버튼을 누를 때만 rfq_triage 전이
#   - v2 nil → 기존 v1 동작 (rfq_pending)
class Gmail::EmailToOrderServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email:    "iss053_#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      name:     "ISS-053 Tester",
      role:     :member
    )
    @account = EmailAccount.create!(
      user:      @user,
      email:     "iss053_acc_#{SecureRandom.hex(3)}@example.com",
      connected: true
    )
  end

  teardown do
    # Order FK: ClassificationLog가 먼저 order_id로 연결되어 있으므로 선 delete
    order_ids = Order.where(user_id: @user.id).pluck(:id)
    ClassificationLog.where(order_id: order_ids).delete_all if order_ids.any?
    ClassificationLog.where(email_message_id: [
      "iss053-msg-confirmed",
      "iss053-msg-excluded",
      "iss053-msg-nil",
      "iss056-dup-msg"
    ]).delete_all
    Order.where(user_id: @user.id).destroy_all
    @account.destroy if EmailAccount.exists?(@account.id)
    @user.destroy if User.exists?(@user.id)
  end

  def build_parsed(id:, subject: "Need quote", body: "Please quote")
    {
      id:         id,
      thread_id:  "thread-#{id}",
      from:       "buyer@example-client.com",
      subject:    subject,
      body:       body,
      html_body:  nil,
      snippet:    body,
      date:       Time.current
    }
  end

  def empty_detection
    {
      is_rfq:        false,
      score:         0,
      confidence:    "none",
      rfq_verdict:   :pending,
      customer_name: nil,
      item_hints:    nil,
      quantities:    nil,
      project_name:  nil,
      delivery_location: nil,
      currency:      nil,
      estimated_value: nil,
      due_date:      nil,
      is_ariba:      false,
      ariba_event_id: nil,
      llm_raw:       {}
    }
  end

  def v2_result(verdict:, confidence: "high", stage_reached: 2, cache_hit: false)
    Gmail::ClassificationResult.new(
      verdict:            verdict,
      is_rfq:             verdict == :confirmed,
      confidence:         confidence,
      stage_reached:      stage_reached,
      classifier_version: "v2",
      reason:             "test_#{verdict}",
      extracted:          {},
      cost_usd:           0.0012,
      latency_ms:         350,
      cache_hit:          cache_hit,
      model:              "haiku-4.5"
    )
  end

  # ===== 1. v2 confirmed 도 rfq_pending — 자동 진입 전면 중단 정책 (2026-04-29) =====
  test "v2_confirmed도 rfq_pending — 자동 칸반 진입 차단" do
    parsed = build_parsed(id: "iss053-msg-confirmed")
    v2 = v2_result(verdict: :confirmed, confidence: "high", stage_reached: 2)

    order = Gmail::EmailToOrderService.new(@account, parsed, empty_detection, v2_result: v2).create_order!

    assert_not_nil order, "Order should be created"
    assert_equal "rfq_pending", order.rfq_status,
      "AI confirmed 여도 rfq_pending — 사용자가 명시적으로 칸반에 보내야 rfq_triage 전이 (자동 진입 전면 중단)"
    assert_equal "v2", order.classifier_version
    assert_equal 2, order.stage_reached
    assert_in_delta 0.95, order.classification_confidence.to_f, 0.001
    assert_equal false, order.cache_hit
  end

  # ===== 2. v2 excluded → rfq_pending (안전 규칙) + would_exclude back-link =====
  test "v2_would_exclude_but_saved_pending: v2 :excluded여도 rfq_pending + would_exclude=true 로그만" do
    parsed = build_parsed(id: "iss053-msg-excluded", subject: "Newsletter")

    # Orchestrator가 Order 생성 전에 log insert 했다고 가정 (order_id=nil)
    pre_log = ClassificationLog.create!(
      classifier_version: "v2",
      email_message_id:   parsed[:id],
      order_id:           nil,
      stage_reached:      1,
      verdict:            "excluded",
      is_rfq:             false,
      confidence:         0.95,
      would_exclude:      false, # back-link 시 true로 업데이트되어야 함
      reason:             "stage1_no_rfq_signal",
      cost_usd:           0.0,
      latency_ms:         12,
      cache_hit:          false,
      model:              "rule-only"
    )

    v2 = v2_result(verdict: :excluded, confidence: "high", stage_reached: 1)
    order = Gmail::EmailToOrderService.new(@account, parsed, empty_detection, v2_result: v2).create_order!

    assert_not_nil order, "Order must still be created for :excluded (Shadow Mode safety)"
    # 핵심 안전 규칙: excluded여도 사용자 화면에 노출되는 rfq_pending
    assert_equal "rfq_pending", order.rfq_status,
      "FATAL: v2 excluded must NOT map to rfq_excluded during Shadow Mode"
    assert_equal "v2", order.classifier_version
    assert_equal 1, order.stage_reached

    # back-link 확인: pre_log가 이 order에 연결되고 would_exclude=true로 마킹됨
    pre_log.reload
    assert_equal order.id, pre_log.order_id
    assert_equal true, pre_log.would_exclude
  end

  # ===== ISS-056: v2_log_id 전달 시 특정 row만 update =====
  test "iss056_v2_log_id는 해당 row만 update — 과거 시도 log는 order에 연결되지 않음" do
    parsed = build_parsed(id: "iss056-dup-msg", subject: "Retry")

    # 재시도 시뮬레이션: 동일 email_message_id로 2개의 log row 생성
    log1 = ClassificationLog.create!(
      classifier_version: "v2",
      email_message_id:   parsed[:id],
      order_id:           nil,
      stage_reached:      2,
      verdict:            "confirmed",
      is_rfq:             true,
      confidence:         0.95,
      would_exclude:      false,
      reason:             "first_call",
      cost_usd:           0.001,
      latency_ms:         100,
      cache_hit:          false,
      model:              "haiku-4.5"
    )
    log2 = ClassificationLog.create!(
      classifier_version: "v2",
      email_message_id:   parsed[:id],
      order_id:           nil,
      stage_reached:      3,
      verdict:            "excluded",
      is_rfq:             false,
      confidence:         0.40,
      would_exclude:      false,
      reason:             "second_call_retry",
      cost_usd:           0.008,
      latency_ms:         500,
      cache_hit:          false,
      model:              "sonnet-4.5"
    )

    v2 = v2_result(verdict: :excluded, confidence: "low", stage_reached: 3)
    order = Gmail::EmailToOrderService.new(
      @account, parsed, empty_detection, v2_result: v2, v2_log_id: log2.id
    ).create_order!

    assert_not_nil order

    log1.reload
    log2.reload
    assert_nil log1.order_id, "log1(과거 시도)은 order에 연결되지 않아야 함 (ISS-056)"
    assert_equal false, log1.would_exclude, "log1은 would_exclude 덮어쓰기 금지"
    assert_equal order.id, log2.order_id, "log2(마지막 시도)만 order에 연결"
    assert_equal true, log2.would_exclude, "log2만 would_exclude=true"
  end

  # ===== 3. v2 nil → 기존 v1 동작 유지 =====
  test "v2_nil_fallback: v2_result nil이면 classifier_version='v1' + rfq_pending" do
    parsed = build_parsed(id: "iss053-msg-nil")

    order = Gmail::EmailToOrderService.new(@account, parsed, empty_detection, v2_result: nil).create_order!

    assert_not_nil order
    assert_equal "rfq_pending", order.rfq_status
    assert_equal "v1", order.classifier_version
    assert_nil order.stage_reached
    assert_nil order.classification_confidence
    assert_equal false, order.cache_hit
  end

  # ===== 좀비 차단: 같은 reference_no 가 archived 면 새 카드도 archived =====
  test "zombie_block: archived ref_no 와 동일한 새 메일은 자동 archived" do
    # 진짜 RFQ 번호 형식(10자리 숫자) — ReferenceNumberExtractor 매칭 필수
    ref = "70000#{rand(10000..99999)}"
    Order.create!(
      title: "old", customer_name: "x", status: :new_rfq,
      reference_no: ref, gmail_thread_id: "old_tid_#{ref}",
      archived_at: Time.current, user: @user
    )

    parsed = build_parsed(id: "zombie-msg-#{ref}", subject: "RFQ #{ref} reminder",
                          body: "Reference #{ref}, please quote ASAP")
    detection = empty_detection.merge(rfq_verdict: :confirmed, is_rfq: true)

    order = Gmail::EmailToOrderService.new(
      @account, parsed, detection, has_rfq_number: true
    ).create_order!

    assert_not_nil order, "좀비 차단 케이스도 카드 자체는 생성되어야 함 (감사 추적용)"
    assert_equal ref, order.reference_no, "ref_no 가 정상 추출되어야 함 (가드 전제)"
    assert order.archived?, "동일 ref_no 가 휴지통에 있으면 새 카드도 archived 로 시작해야 함"
    assert_nil Assignment.find_by(order: order), "auto_archived 카드는 자동배정 스킵"
    assert_equal "auto_archived_zombie_block", order.activities.first&.action
  end

  # ===== 좀비 차단: gmail_thread_id 기반 매칭 =====
  test "zombie_block: archived thread_id 와 동일하면 ref_no 없어도 archived" do
    tid = "ZOMBIE_TID_#{SecureRandom.hex(3)}"
    Order.create!(
      title: "old", customer_name: "x", status: :new_rfq,
      gmail_thread_id: tid, archived_at: Time.current, user: @user
    )

    parsed = build_parsed(id: "zombie-msg-tid-#{tid}", subject: "follow up", body: "any text")
    parsed[:thread_id] = tid

    order = Gmail::EmailToOrderService.new(@account, parsed, empty_detection).create_order!

    assert_not_nil order
    assert order.archived?, "동일 thread 가 휴지통에 있으면 새 카드도 archived"
  end

  # ===== 좀비 차단: archived 가 없으면 정상 생성 (rfq_pending 으로 시작) =====
  test "no_zombie: archived 전적 없으면 정상 생성 (rfq_pending)" do
    ref = "70001#{rand(10000..99999)}"
    parsed = build_parsed(id: "normal-msg-#{ref}", subject: "RFQ #{ref}", body: ref)
    detection = empty_detection.merge(rfq_verdict: :confirmed, is_rfq: true)

    order = Gmail::EmailToOrderService.new(
      @account, parsed, detection, has_rfq_number: true
    ).create_order!

    assert_not_nil order
    assert_not order.archived?, "전적 없으면 archived 안 됨"
    # 2026-04-29 정책: 모든 신규 카드는 rfq_pending. 사용자가 명시적으로 칸반 진입.
    assert_equal "rfq_pending", order.rfq_status, "자동 칸반 진입 전면 중단 — 모든 신규 카드는 rfq_pending"
  end
end
