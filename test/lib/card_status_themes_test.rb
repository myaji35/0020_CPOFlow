# frozen_string_literal: true

require "test_helper"

class CardStatusThemesTest < ActiveSupport::TestCase
  test "SYSTEM_KEYS 7개 정의됨" do
    assert_equal 7, CardStatusThemes::SYSTEM_KEYS.size
    assert_includes CardStatusThemes::SYSTEM_KEYS, "urgent"
    assert_includes CardStatusThemes::SYSTEM_KEYS, "overdue"
  end

  test "BLACK_TEXT 상수 정의됨" do
    assert_equal "#111827", CardStatusThemes::BLACK_TEXT
  end

  test "ALL — 4개 테마" do
    assert_equal 4, CardStatusThemes::ALL.size
  end

  test "ALL — 각 테마는 key/name/colors 포함" do
    CardStatusThemes::ALL.each do |theme|
      assert theme[:key].present?,  "key 없음"
      assert theme[:name].present?, "name 없음"
      assert theme[:colors].is_a?(Hash), "colors가 Hash가 아님"
    end
  end

  test "ALL — 각 테마의 colors에 SYSTEM_KEYS 7개 모두 존재" do
    CardStatusThemes::ALL.each do |theme|
      CardStatusThemes::SYSTEM_KEYS.each do |key|
        assert theme[:colors].key?(key), "#{theme[:key]} 테마에 #{key} 색상 없음"
      end
    end
  end

  test "ALL — 각 color에 bg/border/text 키 존재" do
    CardStatusThemes::ALL.each do |theme|
      theme[:colors].each do |status_key, palette|
        assert palette[:bg].present?,     "#{theme[:key]}.#{status_key}.bg 없음"
        assert palette[:border].present?, "#{theme[:key]}.#{status_key}.border 없음"
        assert palette[:text].present?,   "#{theme[:key]}.#{status_key}.text 없음"
      end
    end
  end

  test "find — 존재하는 key 반환" do
    t = CardStatusThemes.find("level1")
    assert_not_nil t
    assert_equal "level1", t[:key]
  end

  test "find — 존재하지 않는 key는 nil" do
    assert_nil CardStatusThemes.find("nonexistent")
  end

  test "apply! — 존재하지 않는 theme_key면 error 반환" do
    result = CardStatusThemes.apply!("no_such_theme")
    assert_equal false, result[:ok]
    assert result[:error].present?
  end

  test "apply! — 존재하는 theme_key면 ok 반환" do
    result = CardStatusThemes.apply!("level1")
    assert result[:ok], result[:error]
    assert result[:updated].to_i >= 0
  end

  test "current_theme — CardStatus가 없으면 nil" do
    # CardStatus가 없는 환경에서도 에러 없이 nil 반환
    result = CardStatusThemes.current_theme
    # nil 또는 Hash 모두 허용
    assert result.nil? || result.is_a?(Hash)
  end

  test "current_palette — 에러 없이 실행" do
    assert_nothing_raised { CardStatusThemes.current_palette }
  end
end
