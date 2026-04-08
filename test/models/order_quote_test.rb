# frozen_string_literal: true

require "test_helper"

class OrderQuoteTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "oq_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "OQ Test"
    )
    @order = Order.create!(
      user: @user, title: "RFQ", reference_no: "OQ-001",
      status: :new_rfq, customer_name: "Test Customer"
    )
    @supplier = Supplier.create!(name: "Test Supplier #{SecureRandom.hex(4)}")
  end

  test "after_create_commit → quoted_as 링크 자동 생성" do
    assert_difference "OrderLink.count", 1 do
      OrderQuote.create!(order: @order, supplier: @supplier)
    end

    link = OrderLink.where(relation: "quoted_as").last
    assert_equal "quoted_as", link.relation
    assert_equal "confirmed", link.status
    assert_equal @order, link.source
    assert_equal "OrderQuote", link.target_type
    assert_equal "system_event", link.metadata["source"]
    assert_equal "OrderQuote.after_create", link.metadata["trigger"]
  end

  test "같은 OrderQuote 콜백 재실행 시 중복 링크 생성 안 됨 (멱등성)" do
    quote = OrderQuote.create!(order: @order, supplier: @supplier)
    initial_count = OrderLink.count
    quote.send(:create_quoted_link)
    assert_equal initial_count, OrderLink.count, "멱등성 위반: 중복 링크가 생성되었습니다"
  end
end
