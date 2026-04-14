require "test_helper"

class CardStatusTest < ActiveSupport::TestCase
  test "valid factory" do
    cs = CardStatus.new(
      key: "manual_test", name: "수동",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827",
      position: 99
    )
    assert cs.valid?, cs.errors.full_messages.inspect
  end

  test "key unique" do
    CardStatus.create!(
      key: "dup", name: "중복1",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    dup = CardStatus.new(
      key: "dup", name: "중복2",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not dup.valid?
    assert_includes dup.errors[:key], "has already been taken"
  end

  test "hex color format required" do
    cs = CardStatus.new(
      key: "badcolor", name: "bad",
      bg_color: "red", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not cs.valid?
    assert_includes cs.errors[:bg_color].join, "format"
  end

  test "only one default allowed" do
    CardStatus.create!(
      key: "default_a", name: "A", is_default: true,
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_raises(ActiveRecord::RecordNotUnique) do
      CardStatus.create!(
        key: "default_b", name: "B", is_default: true,
        bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
      )
    end
  end

  test "deletable? returns false for system" do
    cs = CardStatus.create!(
      key: "sys_x", name: "sys", is_system: true,
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not cs.deletable?
  end

  test "deletable? returns true when no orders use it" do
    cs = CardStatus.create!(
      key: "free_x", name: "free",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert cs.deletable?
  end

  test "default scope returns the is_default record" do
    skip "orders fixture 포함된 Task 2 이후 검증"
  end
end
