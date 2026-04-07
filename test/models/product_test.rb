# frozen_string_literal: true

require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "name 없으면 유효하지 않음" do
    p = Product.new(name: "")
    assert_not p.valid?
  end

  test "name 있으면 유효" do
    p = Product.new(name: "Test Product")
    assert p.valid?
  end

  test "code 중복이면 유효하지 않음" do
    p1 = Product.create!(name: "Product A", code: "PROD-UNIQ-TEST")
    p2 = Product.new(name: "Product B", code: "PROD-UNIQ-TEST")
    assert_not p2.valid?
    p1.destroy
  end

  test "code blank는 중복 허용" do
    p1 = Product.create!(name: "Product No Code 1", code: "")
    p2 = Product.new(name: "Product No Code 2", code: "")
    assert p2.valid?
    p1.destroy
  end

  test "active scope — active:true 만 반환" do
    p_active   = Product.create!(name: "Active Product #{SecureRandom.hex(4)}", active: true)
    p_inactive = Product.create!(name: "Inactive Product #{SecureRandom.hex(4)}", active: false)
    active_ids = Product.active.pluck(:id)
    assert_includes active_ids, p_active.id
    assert_not_includes active_ids, p_inactive.id
    p_active.destroy; p_inactive.destroy
  end

  test "by_name scope — 알파벳 순 정렬" do
    p1 = Product.create!(name: "ZZZ Product #{SecureRandom.hex(4)}")
    p2 = Product.create!(name: "AAA Product #{SecureRandom.hex(4)}")
    names = Product.by_name.pluck(:name)
    assert names.index { |n| n.start_with?("AAA") } < names.index { |n| n.start_with?("ZZZ") }
    p1.destroy; p2.destroy
  end
end
