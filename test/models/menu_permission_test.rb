# frozen_string_literal: true

require "test_helper"

class MenuPermissionTest < ActiveSupport::TestCase
  def teardown
    MenuPermission.where(role: "member", menu_key: "orders").destroy_all
  end

  test "ROLES 상수 정의됨" do
    assert_includes MenuPermission::ROLES, "admin"
    assert_includes MenuPermission::ROLES, "member"
  end

  test "MENU_KEYS 상수 정의됨" do
    assert_includes MenuPermission::MENU_KEYS, "orders"
    assert_includes MenuPermission::MENU_KEYS, "kanban"
  end

  test "validates — 잘못된 role 거부" do
    perm = MenuPermission.new(role: "superuser", menu_key: "orders")
    assert_not perm.valid?
  end

  test "validates — 잘못된 menu_key 거부" do
    perm = MenuPermission.new(role: "member", menu_key: "unknown_menu")
    assert_not perm.valid?
  end

  test "validates — role + menu_key 유일성" do
    MenuPermission.find_or_create_by(role: "member", menu_key: "orders")
    dup = MenuPermission.new(role: "member", menu_key: "orders")
    assert_not dup.valid?
  end

  test "menu_label — 알려진 키의 한글 레이블" do
    perm = MenuPermission.new(role: "member", menu_key: "orders")
    assert perm.menu_label.is_a?(String)
    assert perm.menu_label.present?
  end

  test "scope for_role — 특정 역할의 권한 반환" do
    result = MenuPermission.for_role("admin")
    assert result.is_a?(ActiveRecord::Relation)
  end
end
