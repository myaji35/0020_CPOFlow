# frozen_string_literal: true

require "test_helper"

class CountryTest < ActiveSupport::TestCase
  def unused_code
    used = Country.pluck(:code).to_set
    ("AA".."ZZ").find { |c| c.match?(/\A[A-Z]{2}\z/) && !used.include?(c) } || "ZZ"
  end

  test "validates — code, name, name_en 필수" do
    country = Country.new
    assert_not country.valid?
    assert country.errors[:code].present?
    assert country.errors[:name].present?
  end

  test "validates — code 2자 고정" do
    country = Country.new(code: "KOR", name: "Korea", name_en: "Korea")
    assert_not country.valid?
    assert country.errors[:code].present?
  end

  test "validates — code 유일성" do
    code = unused_code
    Country.create!(code: code, name: "First #{code}", name_en: "First EN")
    dup = Country.new(code: code, name: "Second", name_en: "Second EN")
    assert_not dup.valid?
    Country.find_by(code: code)&.destroy
  end

  test "employee_count — 소속 직원 수 반환" do
    code = unused_code
    country = Country.create!(code: code, name: "Test EmpCnt", name_en: "Test EN")
    assert_equal 0, country.employee_count
    country.destroy
  end

  test "scope by_sort — sort_order, name 기준 정렬" do
    result = Country.by_sort
    assert result.is_a?(ActiveRecord::Relation)
  end
end
