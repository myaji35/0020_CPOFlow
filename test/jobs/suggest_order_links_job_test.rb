require "test_helper"

class SuggestOrderLinksJobTest < ActiveJob::TestCase
  setup do
    @user = User.find_or_create_by(email: "sj@test.com") do |u|
      u.name = "SJ"
      u.password = "password123"
      u.role = :member
    end
    @client = Client.create!(name: "SJ Client", code: "SJC-#{SecureRandom.hex(3)}", country: "KR", active: true)
  end

  test "같은 Client 90일 내 → suggested 링크 생성" do
    a = Order.create!(user: @user, client: @client, title: "A", customer_name: "C", reference_no: "AA-001", status: :new_rfq)
    Order.create!(user: @user, client: @client, title: "B", customer_name: "C", reference_no: "BB-001", status: :new_rfq)
    OrderLink.where(status: "suggested").delete_all
    SuggestOrderLinksJob.perform_now(a.id)
    assert_operator OrderLink.suggested.count, :>, 0
  end

  test "reference_no prefix 매칭 → suggested 링크 생성" do
    a = Order.create!(user: @user, title: "A", customer_name: "C", reference_no: "ENEC-2026-0042", status: :new_rfq)
    Order.create!(user: @user, title: "B", customer_name: "C", reference_no: "ENEC-2026-0099", status: :new_rfq)
    OrderLink.where(status: "suggested").delete_all
    SuggestOrderLinksJob.perform_now(a.id)
    assert_operator OrderLink.suggested.count, :>, 0
  end

  test "client 없으면 same_client_recent skip (에러 없이)" do
    a = Order.create!(user: @user, title: "X", customer_name: "C", reference_no: "X-001", status: :new_rfq)
    assert_nothing_raised { SuggestOrderLinksJob.perform_now(a.id) }
  end

  test "멱등성 — 2회 실행 시 중복 생성 안 됨" do
    a = Order.create!(user: @user, client: @client, title: "A", customer_name: "C", reference_no: "ID-001", status: :new_rfq)
    Order.create!(user: @user, client: @client, title: "B", customer_name: "C", reference_no: "ID-002", status: :new_rfq)
    OrderLink.where(status: "suggested").delete_all
    SuggestOrderLinksJob.perform_now(a.id)
    after_first = OrderLink.suggested.count
    SuggestOrderLinksJob.perform_now(a.id)
    assert_equal after_first, OrderLink.suggested.count
  end

  test "Order#after_create_commit 콜백이 Job enqueue" do
    assert_enqueued_with(job: SuggestOrderLinksJob) do
      Order.create!(user: @user, title: "Z", customer_name: "C", reference_no: "Z-001", status: :new_rfq)
    end
  end
end
