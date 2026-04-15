# frozen_string_literal: true

require "test_helper"

class EcountSlipCreateJobTest < ActiveJob::TestCase
  def setup
    @user = User.find_or_create_by!(email: "ecount_slip_job_test@example.com") do |u|
      u.name = "Ecount Slip Job Test"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "Slip Job Supplier") do |s|
      s.code = "SLIPJ#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "Slip Job Test Order #{SecureRandom.hex(4)}",
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

  test "job queue" do
    assert_equal "default", EcountSlipCreateJob.new.queue_name
  end

  test "perform — 존재하지 않는 order_id 시 RecordNotFound (discard)" do
    # discard_on 설정에 의해 에러가 발생하지 않음
    assert_nothing_raised { EcountSlipCreateJob.perform_now(0) }
  end

  test "perform — ecount_slip_no 이미 있는 order 시 스킵" do
    @order.update_columns(ecount_slip_no: "EXISTING_SLIP_456")
    assert_nothing_raised { EcountSlipCreateJob.perform_now(@order.id) }
  end
end
