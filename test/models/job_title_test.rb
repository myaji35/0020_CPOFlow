# frozen_string_literal: true

require "test_helper"

class JobTitleTest < ActiveSupport::TestCase
  def setup
    @jt_name = "JT Test Title #{SecureRandom.hex(4)}"
  end

  def teardown
    JobTitle.where("name LIKE ?", "JT Test Title%").destroy_all
  end

  test "validates — name 필수" do
    jt = JobTitle.new(name: "")
    assert_not jt.valid?
    assert jt.errors[:name].present?
  end

  test "validates — name 대소문자 무관 유일성" do
    JobTitle.create!(name: @jt_name)
    dup = JobTitle.new(name: @jt_name.downcase)
    assert_not dup.valid?
  end

  test "create — 유효한 직책 생성" do
    jt = JobTitle.create!(name: @jt_name, active: true)
    assert jt.persisted?
  end

  test "scope active — active: true만 반환" do
    result = JobTitle.active
    assert result.is_a?(ActiveRecord::Relation)
    assert result.all?(&:active)
  end

  test "scope by_sort — sort_order 기준 정렬" do
    result = JobTitle.by_sort
    assert result.is_a?(ActiveRecord::Relation)
  end

  test "employee_count — 숫자 반환" do
    jt = JobTitle.create!(name: @jt_name)
    assert_kind_of Integer, jt.employee_count
  end
end
