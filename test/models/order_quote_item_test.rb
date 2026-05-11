require "test_helper"

class OrderQuoteItemTest < ActiveSupport::TestCase
  fixtures :card_statuses

  setup do
    @user = User.create!(email: "qi-test-#{SecureRandom.hex(4)}@example.com",
                         password: "Pass1234!", name: "QI")
    @order = Order.create!(user: @user, title: "QI 테스트", customer_name: "Test Co",
                           status: :new_rfq)
  end

  test "belongs_to order" do
    item = OrderQuoteItem.new(order: @order, row_no: 1, item: "Test")
    assert item.valid?
    assert_equal @order, item.order
  end

  test "row_no required" do
    item = OrderQuoteItem.new(order: @order, item: "X")
    item.row_no = nil
    assert_not item.valid?
  end

  test "row_no must be positive integer" do
    item = OrderQuoteItem.new(order: @order, item: "X", row_no: 0)
    assert_not item.valid?
    item.row_no = -1
    assert_not item.valid?
    item.row_no = 1
    assert item.valid?
  end

  test "user_edited defaults to false" do
    item = OrderQuoteItem.create!(order: @order, row_no: 1, item: "X")
    assert_equal false, item.user_edited
  end

  test "ordered scope returns by row_no asc" do
    OrderQuoteItem.create!(order: @order, row_no: 3, item: "C")
    OrderQuoteItem.create!(order: @order, row_no: 1, item: "A")
    OrderQuoteItem.create!(order: @order, row_no: 2, item: "B")
    rows = OrderQuoteItem.where(order: @order).ordered.pluck(:item)
    assert_equal %w[A B C], rows
  end

  test "source_attachment optional" do
    item = OrderQuoteItem.new(order: @order, row_no: 1, item: "X")
    assert item.valid?
  end
end
