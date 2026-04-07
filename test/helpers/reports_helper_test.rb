# frozen_string_literal: true

require "test_helper"

class ReportsHelperTest < ActionView::TestCase
  include ReportsHelper

  test "delta_badge — prev_val nil이면 빈 문자열" do
    result = delta_badge(100, nil)
    assert_equal "", result
  end

  test "delta_badge — prev_val 0이면 빈 문자열" do
    result = delta_badge(100, 0)
    assert_equal "", result
  end

  test "delta_badge — 양수 증가 → 초록 arrow up" do
    result = delta_badge(110, 100)
    assert_includes result, "▲"
    assert_includes result, "green"
    assert_includes result, "10.0%"
  end

  test "delta_badge — 음수 감소 → 빨강 arrow down" do
    result = delta_badge(90, 100)
    assert_includes result, "▼"
    assert_includes result, "red"
    assert_includes result, "10.0%"
  end

  test "delta_badge — 동일 값 → 양수로 처리 (0.0%)" do
    result = delta_badge(100, 100)
    assert_includes result, "▲"
    assert_includes result, "0.0%"
  end
end
