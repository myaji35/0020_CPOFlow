# frozen_string_literal: true

require "test_helper"

class OrderQuoteItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_or_create_by(email: "qic-ctrl-test@example.com") do |u|
      u.name = "QIC Test"
      u.password = "password123"
      u.role = :member
    end
    @order = Order.create!(reference_no: "QIC-#{SecureRandom.hex(3)}",
                           title: "T", user: @user, customer_name: "CN")
    login_as(@user)
  end

  teardown do
    @order.quote_items.destroy_all
    @order.reload.destroy if Order.exists?(@order.id)
  end

  test "index renders empty state when no items" do
    get order_quote_items_path(@order), as: :turbo_stream
    assert_response :success
    assert_match "품목이 아직 없습니다", response.body
  end

  test "create adds row (empty → frame replace)" do
    assert_difference -> { @order.quote_items.count }, 1 do
      post order_quote_items_path(@order), as: :turbo_stream
    end
    assert_response :success
    item = @order.quote_items.last
    assert_equal 1, item.row_no
  end

  test "create appends row when items exist" do
    @order.quote_items.create!(row_no: 1, item: "Existing")
    assert_difference -> { @order.quote_items.count }, 1 do
      post order_quote_items_path(@order), as: :turbo_stream
    end
    assert_response :success
    new_item = @order.quote_items.order(:row_no).last
    assert_equal 2, new_item.row_no
  end

  test "destroy removes row" do
    item = @order.quote_items.create!(row_no: 1, item: "X")
    assert_difference -> { @order.quote_items.count }, -1 do
      delete order_quote_item_path(@order, item), as: :turbo_stream
    end
    assert_response :success
  end

  test "index lists existing items" do
    @order.quote_items.create!(row_no: 1, item: "SPILL TRAY", qty: 16, unit: "EA")
    get order_quote_items_path(@order), as: :turbo_stream
    assert_response :success
    assert_match "SPILL TRAY", response.body
  end

  test "update sets value + user_edited" do
    item = @order.quote_items.create!(row_no: 1, item: "Old")
    patch order_quote_item_path(@order, item),
          params: { field: "item", value: "New" }, as: :turbo_stream
    assert_response :success
    item.reload
    assert_equal "New", item.item
    assert_equal true, item.user_edited
    assert_equal @user.id, item.edited_by_user_id
  end

  test "update rejects unknown field" do
    item = @order.quote_items.create!(row_no: 1, item: "X")
    patch order_quote_item_path(@order, item),
          params: { field: "ssn", value: "123" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "update normalizes qty" do
    item = @order.quote_items.create!(row_no: 1, item: "X")
    patch order_quote_item_path(@order, item),
          params: { field: "qty", value: "16 EA" }, as: :turbo_stream
    item.reload
    assert_equal 16, item.qty.to_i
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
