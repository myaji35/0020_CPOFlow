# frozen_string_literal: true

require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  def setup
    @country = Country.first || Country.create!(
      code: "CT", name: "Company Test Country", name_en: "Company Test Country EN"
    )
  end

  test "validates — name 필수" do
    company = Company.new(company_type: "hq", country: @country)
    assert_not company.valid?
    assert company.errors[:name].present?
  end

  test "validates — company_type 허용 외 값 거부" do
    company = Company.new(name: "Test Co", country: @country)
    company.write_attribute(:company_type, "invalid_type")
    assert_not company.valid?
    assert company.errors[:company_type].present?
  end

  test "validates — company_type 허용값 확인" do
    company = Company.new(name: "Test Corp", company_type: "invalid", country: @country)
    assert_not company.valid?
    assert company.errors[:company_type].present?
  end

  test "create — 유효한 company 생성" do
    company = Company.create!(
      name: "Test Company #{SecureRandom.hex(4)}",
      company_type: "hq",
      country: @country,
      active: true
    )
    assert company.persisted?
    company.destroy
  end

  test "company_type_label — 한글 레이블 반환" do
    company = Company.new(company_type: "hq")
    assert_equal "본사", company.company_type_label
  end

  test "employee_count — 소속 직원 수 반환" do
    company = Company.create!(name: "EmpCnt Corp #{SecureRandom.hex(4)}", company_type: "branch", country: @country)
    assert_equal 0, company.employee_count
    company.destroy
  end

  test "scope active — active: true만 반환" do
    result = Company.active
    assert result.is_a?(ActiveRecord::Relation)
    assert result.all? { |c| c.active }
  end
end
