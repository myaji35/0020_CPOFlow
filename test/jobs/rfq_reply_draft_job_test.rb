# frozen_string_literal: true

require "test_helper"

class RfqReplyDraftJobTest < ActiveJob::TestCase
  def setup
    @user = User.find_or_create_by!(email: "rfq_draft_job_test@example.com") do |u|
      u.name = "RFQ Draft Job Tester"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "RFQ Draft Job Supplier") do |s|
      s.code = "RDJS#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "RFQ Draft Job Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          @user,
      supplier:      @supplier
    )
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "perform — order not found 시 에러 없이 종료" do
    assert_nothing_raised { RfqReplyDraftJob.perform_now(0) }
  end

  test "perform — 유효한 order_id 전달 시 에러 없이 실행" do
    # API 미설정 환경에서도 rescue로 처리됨
    assert_nothing_raised { RfqReplyDraftJob.perform_now(@order.id) }
  end

  test "job queue" do
    assert_equal "default", RfqReplyDraftJob.new.queue_name
  end
end
