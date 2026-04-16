require "test_helper"

class KanbanBoardTest < ActiveSupport::TestCase
  test "validates name presence" do
    board = KanbanBoard.new(board_type: "purchase")
    assert_not board.valid?
    assert_includes board.errors[:name], "can't be blank"
  end

  test "validates board_type inclusion" do
    board = KanbanBoard.new(name: "Test", board_type: "invalid")
    assert_not board.valid?
  end

  test "valid board creates successfully" do
    board = KanbanBoard.new(name: "영업보드", board_type: "sales", color_palette: "vivid")
    assert board.valid?
  end

  test "ensure_default! creates default board" do
    KanbanBoard.destroy_all
    KanbanBoard.ensure_default!
    assert_equal 1, KanbanBoard.where(is_default: true).count
  end

  test "has_many card_statuses" do
    board = KanbanBoard.create!(name: "Test", board_type: "custom")
    assert_respond_to board, :card_statuses
  end

  test "has_many orders" do
    board = KanbanBoard.create!(name: "Test", board_type: "custom")
    assert_respond_to board, :orders
  end
end
