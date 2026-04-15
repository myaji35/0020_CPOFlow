# frozen_string_literal: true

require "test_helper"

class AribaFetchJobTest < ActiveJob::TestCase
  def setup
    @user = User.find_or_create_by!(email: "ariba_fetch_job_test@example.com") do |u|
      u.name = "Ariba Fetch Job Test"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "Ariba Fetch Supplier") do |s|
      s.code = "ARBFJ#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "Ariba Fetch Test Order #{SecureRandom.hex(4)}",
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
    assert_equal "default", AribaFetchJob.new.queue_name
  end

  test "perform — RecordNotFound 시 discard (에러 없음)" do
    assert_nothing_raised { AribaFetchJob.perform_now(order_id: 0) }
  end

  test "perform — sap_portal_links 없는 order는 빠르게 완료" do
    # SAP 자격증명 없는 환경에서 Ariba 링크 없으면 조기 반환
    assert_nothing_raised { AribaFetchJob.perform_now(order_id: @order.id) }
  end
end
