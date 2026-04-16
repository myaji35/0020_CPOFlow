# frozen_string_literal: true

require "test_helper"

class KanbanColumnTest < ActiveSupport::TestCase
  setup do
    @board = KanbanBoard.ensure_default!
  end

  test "validates name presence" do
    col = KanbanColumn.new(kanban_board: @board, key: "test_col")
    assert_not col.valid?
    assert_includes col.errors[:name], "can't be blank"
  end

  test "auto-generates key from name" do
    col = KanbanColumn.new(kanban_board: @board, name: "Review Stage")
    col.valid?
    assert_equal "review_stage", col.key
  end

  test "auto-generates key from Korean name" do
    col = KanbanColumn.new(kanban_board: @board, name: "검토 단계")
    col.valid?
    # Korean chars removed, fallback to col_ + hex
    assert_match(/\Acol_[a-f0-9]{6}\z/, col.key)
  end

  test "validates key uniqueness within board" do
    KanbanColumn.create!(kanban_board: @board, name: "Test", key: "unique_test_key", position: 99)
    dup = KanbanColumn.new(kanban_board: @board, name: "Test 2", key: "unique_test_key")
    assert_not dup.valid?
    assert_includes dup.errors[:key], "has already been taken"
  end

  test "validates key format" do
    col = KanbanColumn.new(kanban_board: @board, name: "Bad", key: "Bad-Key!")
    assert_not col.valid?
    assert_includes col.errors[:key], "is invalid"
  end

  test "ordered scope returns by position" do
    @board.kanban_columns.destroy_all
    c1 = KanbanColumn.create!(kanban_board: @board, name: "B", key: "b_col", position: 2)
    c2 = KanbanColumn.create!(kanban_board: @board, name: "A", key: "a_col", position: 1)
    assert_equal [c2, c1], @board.kanban_columns.ordered.to_a
  end

  test "validates name max length" do
    col = KanbanColumn.new(kanban_board: @board, name: "a" * 41, key: "long_name")
    assert_not col.valid?
    assert_includes col.errors[:name], "is too long (maximum is 40 characters)"
  end
end
