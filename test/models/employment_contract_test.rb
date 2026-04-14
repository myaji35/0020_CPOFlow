# frozen_string_literal: true

require "test_helper"

class EmploymentContractTest < ActiveSupport::TestCase
  def setup
    @employee = Employee.create!(
      name: "EC Emp #{SecureRandom.hex(3)}", nationality: "KR",
      employment_type: "regular"
    )
  end

  def teardown
    EmploymentContract.where(employee: @employee).destroy_all
    @employee.destroy if Employee.exists?(@employee.id)
  end

  test "CONTRACT_STATUSES 상수 정의됨" do
    assert_includes EmploymentContract::CONTRACT_STATUSES, "active"
    assert_includes EmploymentContract::CONTRACT_STATUSES, "expired"
    assert_includes EmploymentContract::CONTRACT_STATUSES, "terminated"
    assert_includes EmploymentContract::CONTRACT_STATUSES, "renewed"
  end

  test "PAY_FREQUENCIES 상수 정의됨" do
    assert_includes EmploymentContract::PAY_FREQUENCIES, "monthly"
    assert_includes EmploymentContract::PAY_FREQUENCIES, "weekly"
  end

  test "validates — 잘못된 status 거부 (write_attribute로 기본값 우회)" do
    ec = EmploymentContract.new(employee: @employee, start_date: Date.today)
    ec.write_attribute(:status, "invalid_status")
    assert_not ec.valid?
    assert ec.errors[:status].present?
  end

  test "validates — 잘못된 status 거부" do
    ec = EmploymentContract.new(employee: @employee, start_date: Date.today, status: "invalid")
    assert_not ec.valid?
  end

  test "create — 유효한 계약 생성" do
    ec = EmploymentContract.create!(employee: @employee, start_date: Date.today, status: "active")
    assert ec.persisted?
  end

  test "status_label — 한글 레이블" do
    assert_equal "계약중", EmploymentContract.new(status: "active").status_label
    assert_equal "만료",   EmploymentContract.new(status: "expired").status_label
    assert_equal "해지",   EmploymentContract.new(status: "terminated").status_label
    assert_equal "갱신됨", EmploymentContract.new(status: "renewed").status_label
  end

  test "pay_frequency_label — 한글 레이블" do
    assert_equal "월급", EmploymentContract.new(pay_frequency: "monthly").pay_frequency_label
    assert_equal "주급", EmploymentContract.new(pay_frequency: "weekly").pay_frequency_label
  end

  test "scope active — active만 반환" do
    result = EmploymentContract.active
    assert result.is_a?(ActiveRecord::Relation)
    result.each { |ec| assert_equal "active", ec.status }
  end
end
