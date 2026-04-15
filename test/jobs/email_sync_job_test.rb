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
end
