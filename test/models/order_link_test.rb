require "test_helper"

class OrderLinkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "order_link_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Order Link Test"
    )
    @order_a = Order.create!(
      user: @user,
      title: "RFQ A",
      customer_name: "Test Customer",
      reference_no: "TEST-001",
      status: :new_rfq
    )
    @order_b = Order.create!(
      user: @user,
      title: "PO B",
      customer_name: "Test Customer",
      reference_no: "TEST-001",
      status: :new_po
    )
  end

  test "polymorphic source/target 양쪽 set 시 valid" do
    link = OrderLink.new(
      source: @order_a, target: @order_b,
      relation: "derived_from", status: "confirmed", confidence: 1.0
    )
    assert link.valid?, link.errors.full_messages.join(", ")
  end

  test "relation 화이트리스트 미포함 시 invalid" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "bogus")
    assert_not link.valid?
    # 메시지 문자열이 아니라 에러 종류를 검증한다. locale.rb가
    # production=:en / 그 외=:ko 로 분기해 test 환경에서는 한국어가 나온다.
    assert link.errors.of_kind?(:relation, :inclusion)
  end

  test "status 화이트리스트 미포함 시 invalid" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "references", status: "bogus")
    assert_not link.valid?
  end

  test "confidence 0.0~1.0 범위 강제" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "references", confidence: 1.5)
    assert_not link.valid?
  end

  test "metadata JSON serialize/deserialize" do
    link = OrderLink.create!(
      source: @order_a, target: @order_b, relation: "references",
      metadata: { source: "manual", note: "테스트" }
    )
    link.reload
    assert_equal "manual", link.metadata["source"]
    assert_equal "테스트", link.metadata["note"]
  end

  test "for_node scope — source 또는 target 매칭" do
    OrderLink.create!(source: @order_a, target: @order_b, relation: "references")
    assert_equal 1, OrderLink.for_node(@order_a).count
    assert_equal 1, OrderLink.for_node(@order_b).count
  end
end
