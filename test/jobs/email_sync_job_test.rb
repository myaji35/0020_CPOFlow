# frozen_string_literal: true

require "test_helper"

class EmailSyncJobTest < ActiveJob::TestCase
  def setup
    @user = User.find_or_create_by!(email: "email_sync_job_test@example.com") do |u|
      u.name = "Email Sync Job Test"; u.password = "password123"; u.role = :member
    end
  end

  test "perform_later enqueue 가능" do
    assert_enqueued_with(job: EmailSyncJob) do
      EmailSyncJob.perform_later
    end
  end

  test "perform_later — account_id 파라미터로 enqueue" do
    assert_enqueued_with(job: EmailSyncJob) do
      EmailSyncJob.perform_later(account_id: 9999)
    end
  end

  test "큐 이름 — default" do
    assert_equal "default", EmailSyncJob.new.queue_name
  end

  test "discard_on RecordNotFound — 없는 account_id는 에러 없이 폐기" do
    assert_nothing_raised do
      perform_enqueued_jobs do
        EmailSyncJob.perform_later(account_id: 99999999)
      end
    end
  end

  test "perform — 연결된 계정 없으면 아무것도 안 함" do
    # connected: false 계정만 있을 때 perform은 정상 종료
    @user.email_accounts.update_all(connected: false) if @user.email_accounts.any?
    assert_nothing_raised do
      EmailSyncJob.new.perform
    end
  end

  test "perform — account_id에 연결된 계정이 없으면 RecordNotFound 발생" do
    assert_raises(ActiveRecord::RecordNotFound) do
      EmailSyncJob.new.perform(account_id: 99999999)
    end
  end

  test "perform — synced_recently? true인 계정은 skip" do
    account = EmailAccount.create!(
      user: @user, email: "sync_recent_#{SecureRandom.hex(3)}@example.com",
      connected: true, last_synced_at: 1.minute.ago
    )
    # synced_recently? = true이므로 sync_account 내부 로직은 실행되지 않음 (에러 없음)
    assert_nothing_raised do
      EmailSyncJob.new.perform(account_id: account.id)
    end
    account.destroy
  end

  test "perform — ready? false인 계정은 skip (토큰 만료)" do
    account = EmailAccount.create!(
      user: @user, email: "sync_expired_#{SecureRandom.hex(3)}@example.com",
      connected: true, last_synced_at: nil,
      token_expires_at: 1.hour.ago
    )
    # ready?가 false이므로 Gmail API 호출 없이 skip (에러 없음)
    assert_nothing_raised do
      EmailSyncJob.new.perform(account_id: account.id, force: true)
    end
    account.destroy
  end

  # ISS-309: record_po_receipt — status를 절대 바꾸지 않는다는 것을 검증
  test "record_po_receipt — Order status를 변경하지 않는다" do
    account = EmailAccount.create!(
      user: @user, email: "iss309_job_#{SecureRandom.hex(3)}@example.com", connected: true
    )
    order = Order.create!(
      title: "ISS-309 status guard", customer_name: "Client", user_id: @user.id,
      status: :pending_po, gmail_thread_id: "thread-iss309-job"
    )
    parsed = { id: "gmail-msg-iss309-1", subject: "Purchase Order confirmed", thread_id: "thread-iss309-job" }
    po_result = { is_po: true, po_number: "PO-JOB-001", matched_keyword: "Purchase Order", confidence: "high" }

    EmailSyncJob.new.send(:record_po_receipt, order, parsed, po_result, account)
    order.reload

    assert_equal "pending_po", order.status
    assert order.po_detected_at.present?
    assert_equal "gmail-msg-iss309-1", order.po_source_email_id
    assert_equal "PO-JOB-001", order.po_no

    order.destroy
    account.destroy
  end

  test "record_po_receipt — 멱등: 동일 메일 재처리 시 아무것도 하지 않는다" do
    account = EmailAccount.create!(
      user: @user, email: "iss309_job2_#{SecureRandom.hex(3)}@example.com", connected: true
    )
    detected_at = 1.day.ago.change(usec: 0)
    order = Order.create!(
      title: "ISS-309 idempotent", customer_name: "Client", user_id: @user.id,
      po_detected_at: detected_at, po_source_email_id: "gmail-msg-iss309-2"
    )
    parsed = { id: "gmail-msg-iss309-2", subject: "Purchase Order confirmed" }
    po_result = { is_po: true, po_number: "PO-JOB-002", matched_keyword: "Purchase Order", confidence: "high" }

    activity_count_before = Activity.where(order_id: order.id).count
    EmailSyncJob.new.send(:record_po_receipt, order, parsed, po_result, account)
    order.reload

    assert_equal detected_at, order.po_detected_at
    assert_nil order.po_no # 재처리로 덮어써지지 않음
    assert_equal activity_count_before, Activity.where(order_id: order.id).count

    order.destroy
    account.destroy
  end

  test "record_po_receipt — Activity를 생성한다" do
    account = EmailAccount.create!(
      user: @user, email: "iss309_job3_#{SecureRandom.hex(3)}@example.com", connected: true
    )
    order = Order.create!(
      title: "ISS-309 activity", customer_name: "Client", user_id: @user.id
    )
    parsed = { id: "gmail-msg-iss309-3", subject: "PO Number: PO-JOB-003" }
    po_result = { is_po: true, po_number: "PO-JOB-003", matched_keyword: "PO Number", confidence: "high" }

    assert_difference -> { Activity.where(order_id: order.id).count }, 1 do
      EmailSyncJob.new.send(:record_po_receipt, order, parsed, po_result, account)
    end

    activity = Activity.where(order_id: order.id).last
    assert_equal "po_email_detected", activity.action
    assert_equal @user.id, activity.user_id

    order.destroy
    account.destroy
  end
end
