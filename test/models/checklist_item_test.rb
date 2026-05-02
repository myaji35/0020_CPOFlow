require "test_helper"

class ChecklistItemTest < ActiveSupport::TestCase
  test "코드 형식 검증 (대문자/숫자/언더스코어)" do
    refute ChecklistItem.new(code: "lower", name: "x", prompt_hint: "y", category: "general").valid?
    refute ChecklistItem.new(code: "WITH-DASH", name: "x", prompt_hint: "y", category: "general").valid?
    assert ChecklistItem.new(code: "AQ_GRADE", name: "x", prompt_hint: "y", category: "general").valid?
    assert ChecklistItem.new(code: "ITEM_12_X", name: "x", prompt_hint: "y", category: "general").valid?
  end

  test "코드 unique" do
    ChecklistItem.create!(code: "DUP_TEST", name: "a", prompt_hint: "h", category: "general")
    refute ChecklistItem.new(code: "DUP_TEST", name: "b", prompt_hint: "h", category: "general").valid?
  end

  test "category 화이트리스트" do
    refute ChecklistItem.new(code: "BAD_CAT", name: "x", prompt_hint: "y", category: "invalid").valid?
    ChecklistItem::CATEGORIES.each do |cat|
      assert ChecklistItem.new(code: "OK_#{cat.upcase}", name: "x", prompt_hint: "y", category: cat).valid?
    end
  end

  test "allowed_values_array — JSON round-trip" do
    item = ChecklistItem.create!(code: "AQ_TEST", name: "AQ", prompt_hint: "h", category: "quality")
    item.allowed_values_array = %w[A B C Reject]
    item.save!
    assert_equal %w[A B C Reject], item.reload.allowed_values_array
  end

  test "allowed_values_array — 빈 배열 시 nil 저장" do
    item = ChecklistItem.create!(code: "EMPTY_AV", name: "x", prompt_hint: "h", category: "general")
    item.allowed_values_array = []
    assert_nil item.allowed_values
    assert_equal [], item.allowed_values_array
  end

  test "prompt_fragment — allowed_values 있을 때 형식" do
    item = ChecklistItem.create!(code: "FRG_AQ", name: "x", prompt_hint: "AQ 등급 추출", category: "quality", required: true)
    item.allowed_values_array = %w[A B C]
    item.save!
    frag = item.prompt_fragment
    assert_match(/FRG_AQ/, frag)
    assert_match(/AQ 등급 추출/, frag)
    assert_match(/allowed: A, B, C/, frag)
    assert_match(/REQUIRED/, frag)
  end

  test "active scope" do
    ChecklistItem.create!(code: "ACT_1", name: "a", prompt_hint: "h", category: "general", active: true)
    ChecklistItem.create!(code: "ACT_2", name: "b", prompt_hint: "h", category: "general", active: false)
    codes = ChecklistItem.active.pluck(:code)
    assert_includes codes, "ACT_1"
    refute_includes codes, "ACT_2"
  end
end
