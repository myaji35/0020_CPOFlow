# frozen_string_literal: true

require "test_helper"

class DepartmentTest < ActiveSupport::TestCase
  def setup
    country = Country.first || Country.create!(code: "DT", name: "Dept Test Country", name_en: "Dept Test EN")
    @company = Company.create!(
      name: "Dept Test Company #{SecureRandom.hex(4)}",
      company_type: "hq",
      country: country,
      active: true
    )
  end

  def teardown
    @company.destroy if Company.exists?(@company.id)
  end

  test "validates — name 필수" do
    dept = @company.departments.build(name: "")
    assert_not dept.valid?
    assert dept.errors[:name].present?
  end

  test "validates — company 내 name 유일성" do
    @company.departments.create!(name: "유일 부서명")
    dup = @company.departments.build(name: "유일 부서명")
    assert_not dup.valid?
    @company.departments.destroy_all
  end

  test "full_name — 부모 없으면 name만 반환" do
    dept = @company.departments.create!(name: "개발팀")
    assert_equal "개발팀", dept.full_name
    dept.destroy
  end

  test "full_name — 부모 있으면 Parent > name 형식" do
    parent = @company.departments.create!(name: "IT본부")
    child  = @company.departments.create!(name: "개발1팀", parent: parent)
    assert_equal "IT본부 > 개발1팀", child.full_name
    child.destroy
    parent.destroy
  end

  test "scope active — active: true 필터" do
    result = Department.active
    assert result.is_a?(ActiveRecord::Relation)
  end

  test "scope root_level — parent_id nil 필터" do
    result = Department.root_level
    assert result.is_a?(ActiveRecord::Relation)
    assert result.all? { |d| d.parent_id.nil? }
  end
end
