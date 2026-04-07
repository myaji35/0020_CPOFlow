require "test_helper"

class OrderExtendedTest < ActiveSupport::TestCase
  # display_subject 테스트
  test "display_subject: RE: 접두사 제거" do
    order = Order.new(title: "Test Order", customer_name: "Test Co",
                      original_email_subject: "RE: 견적 요청")
    assert_equal "견적 요청", order.display_subject
  end

  test "display_subject: 중첩 RE:/FW: 접두사 제거" do
    order = Order.new(title: "Test Order", customer_name: "Test Co",
                      original_email_subject: "RE: RE: FW: 견적 요청")
    assert_equal "견적 요청", order.display_subject
  end

  test "display_subject: original_email_subject 없으면 title 반환" do
    order = Order.new(title: "Test Order", customer_name: "Test Co",
                      original_email_subject: "")
    assert_equal "Test Order", order.display_subject
  end

  test "display_subject: Event 접두사 제거" do
    order = Order.new(title: "Test Order", customer_name: "Test Co",
                      original_email_subject: "Event 견적 요청")
    assert_equal "견적 요청", order.display_subject
  end

  test "display_subject: RFQ 접두사 제거" do
    order = Order.new(title: "Test Order", customer_name: "Test Co",
                      original_email_subject: "RFQ: 자재 구매 요청")
    assert_equal "자재 구매 요청", order.display_subject
  end

  # subject_tags 테스트
  test "subject_tags: reminder 태그 감지" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      original_email_subject: "Reminder: 견적 요청")
    assert_includes order.subject_tags, "Reminder"
  end

  test "subject_tags: 태그 없으면 빈 배열" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      original_email_subject: "일반 견적 요청")
    assert_empty order.subject_tags
  end

  test "subject_tags: urgent 태그 감지" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      original_email_subject: "URGENT: 납품 요청")
    assert_includes order.subject_tags, "Urgent"
  end

  # days_until_due 테스트
  test "days_until_due: due_date 없으면 nil" do
    order = Order.new(title: "Test", customer_name: "Test Co")
    assert_nil order.days_until_due
  end

  test "days_until_due: 미래 날짜면 양수" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 5.days.from_now.to_date)
    assert order.days_until_due > 0
  end

  test "days_until_due: 과거 날짜면 음수" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 3.days.ago.to_date)
    assert order.days_until_due < 0
  end

  # due_urgency 테스트
  test "due_urgency: due_date 없으면 :normal" do
    order = Order.new(title: "Test", customer_name: "Test Co")
    assert_equal :normal, order.due_urgency
  end

  test "due_urgency: 오늘 이전이면 :overdue" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 1.day.ago.to_date)
    assert_equal :overdue, order.due_urgency
  end

  test "due_urgency: 7일 이내면 :urgent" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 5.days.from_now.to_date)
    assert_equal :urgent, order.due_urgency
  end

  test "due_urgency: 14일 이내면 :warning" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 10.days.from_now.to_date)
    assert_equal :warning, order.due_urgency
  end

  test "due_urgency: 14일 초과면 :normal" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 20.days.from_now.to_date)
    assert_equal :normal, order.due_urgency
  end

  # due_badge_class 테스트
  test "due_badge_class: overdue면 badge-danger" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 1.day.ago.to_date)
    assert_equal "badge-danger", order.due_badge_class
  end

  test "due_badge_class: normal이면 badge-success" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      due_date: 20.days.from_now.to_date)
    assert_equal "badge-success", order.due_badge_class
  end

  # tags_array 테스트
  test "tags_array: 쉼표 구분 태그 파싱" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      tags: "urgent, important, review")
    assert_equal %w[urgent important review], order.tags_array
  end

  test "tags_array: 태그 없으면 빈 배열" do
    order = Order.new(title: "Test", customer_name: "Test Co", tags: nil)
    assert_equal [], order.tags_array
  end

  # email_signature 테스트
  test "email_signature: 빈 JSON이면 빈 Hash" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      email_signature_json: nil)
    assert_equal({}, order.email_signature)
  end

  test "email_signature: 유효한 JSON 파싱" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      email_signature_json: '{"name":"John","company":"ACME"}')
    sig = order.email_signature
    assert_equal "John", sig[:name]
    assert_equal "ACME", sig[:company]
  end

  test "email_signature: 잘못된 JSON이면 빈 Hash" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      email_signature_json: "invalid json{")
    assert_equal({}, order.email_signature)
  end

  # sender_name 테스트
  test "sender_name: email_signature에 name 있으면 반환" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      email_signature_json: '{"name":"Alice"}',
                      original_email_from: "alice@example.com")
    assert_equal "Alice", order.sender_name
  end

  test "sender_name: email_signature 없으면 From 헤더에서 추출" do
    order = Order.new(title: "Test", customer_name: "Test Co",
                      email_signature_json: nil,
                      original_email_from: "Bob Smith <bob@example.com>")
    assert_equal "Bob Smith", order.sender_name
  end

  # sender_company 테스트
  test "sender_company: email_signature에 company 있으면 반환" do
    order = Order.new(title: "Test", customer_name: "FALLBACK Co",
                      email_signature_json: '{"company":"ACME Corp"}')
    assert_equal "ACME Corp", order.sender_company
  end

  test "sender_company: email_signature 없으면 customer_name 반환" do
    order = Order.new(title: "Test", customer_name: "FALLBACK Co",
                      email_signature_json: nil)
    assert_equal "FALLBACK Co", order.sender_company
  end

  # enum 범위 스코프
  test "inbox_pending scope 동작" do
    assert_nothing_raised { Order.inbox_pending.count }
  end

  test "inbox_excluded scope 동작" do
    assert_nothing_raised { Order.inbox_excluded.count }
  end

  test "inbox_triaged scope 동작" do
    assert_nothing_raised { Order.inbox_triaged.count }
  end

  test "root_orders scope 동작" do
    assert_nothing_raised { Order.root_orders.count }
  end

  test "due_soon scope 동작" do
    assert_nothing_raised { Order.due_soon.count }
  end

  # KANBAN_COLUMNS 상수
  test "KANBAN_COLUMNS에 9개 상태 존재" do
    assert_equal 9, Order::KANBAN_COLUMNS.length
  end

  # STATUS_LABELS 상수
  test "STATUS_LABELS에 new_rfq 레이블 존재" do
    assert Order::STATUS_LABELS.key?("new_rfq")
  end

  # task_progress (tasks 없을 때)
  test "task_progress: tasks 없으면 done:0, total:0" do
    order = Order.new(title: "Test", customer_name: "Test Co")
    assert_equal({ done: 0, total: 0 }, order.task_progress)
  end

  # rfq_status enum
  test "rfq_status enum 유효" do
    %w[rfq_triage rfq_pending rfq_excluded rfq_archived].each do |s|
      assert Order.rfq_statuses.key?(s), "rfq_status #{s} 누락"
    end
  end

  # source_type enum
  test "source_type enum 유효" do
    %w[email ariba].each do |s|
      assert Order.source_types.key?(s), "source_type #{s} 누락"
    end
  end
end
