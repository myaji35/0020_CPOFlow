require "test_helper"

class KanbanBoardTest < ActiveSupport::TestCase
  test "validates name presence" do
    board = KanbanBoard.new(board_type: "purchase")
    assert_not board.valid?
    # 에러 메시지 문자열이 아니라 "name에 blank 에러가 붙었는가"를 검증한다.
    # locale.rb가 production=:en / 그 외=:ko 로 분기하므로 "can't be blank"를
    # 하드코딩하면 test 환경(:ko)에서 항상 깨진다. 로케일 무관하게 동작을 본다.
    assert board.errors.of_kind?(:name, :blank)
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
