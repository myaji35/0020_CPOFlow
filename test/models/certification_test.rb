# frozen_string_literal: true

require "test_helper"

class CertificationTest < ActiveSupport::TestCase
  def setup
    @employee = Employee.create!(
      name: "Cert Emp #{SecureRandom.hex(3)}", nationality: "KR",
      employment_type: "regular"
    )
  end

  def teardown
    Certification.where(employee: @employee).destroy_all
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "validates — name 필수" do
    cert = Certification.new(employee: @employee, name: "")
    assert_not cert.valid?
    assert cert.errors[:name].present?
  end

  test "create — 유효한 자격증 생성" do
    cert = Certification.create!(employee: @employee, name: "AWS 자격증")
    assert cert.persisted?
  end

  test "expired? — 만료일 과거이면 true" do
    cert = Certification.new(expiry_date: 1.day.ago.to_date)
    assert cert.expired?
  end

  test "expired? — 만료일 없으면 false" do
    cert = Certification.new(expiry_date: nil)
    assert_not cert.expired?
  end

  test "expiring_soon? — 30일 이내이면 true" do
    cert = Certification.new(expiry_date: 10.days.from_now.to_date)
    assert cert.expiring_soon?
  end

  test "expiring_soon? — 31일 이후이면 false" do
    cert = Certification.new(expiry_date: 60.days.from_now.to_date)
    assert_not cert.expiring_soon?
  end

  test "scope by_expiry — 만료일 오름차순 정렬" do
    result = Certification.by_expiry
    assert result.is_a?(ActiveRecord::Relation)
  end

  test "expiry_badge_class — 만료 시 red" do
    cert = Certification.new(expiry_date: 1.day.ago.to_date)
    assert_includes cert.expiry_badge_class, "red"
  end

  test "expiry_badge_class — soon 시 yellow" do
    cert = Certification.new(expiry_date: 10.days.from_now.to_date)
    assert_includes cert.expiry_badge_class, "yellow"
  end

  test "expiry_badge_class — 정상 시 green" do
    cert = Certification.new(expiry_date: 200.days.from_now.to_date)
    assert_includes cert.expiry_badge_class, "green"
  end
end
