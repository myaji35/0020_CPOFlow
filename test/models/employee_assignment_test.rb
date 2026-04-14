# frozen_string_literal: true

require "test_helper"

class EmployeeAssignmentTest < ActiveSupport::TestCase
  def setup
    @employee = Employee.create!(
      name: "EA Emp #{SecureRandom.hex(3)}", nationality: "KR",
      employment_type: "regular"
    )
    @client  = Client.find_or_create_by!(name: "EA Test Client") { |c| c.code = "EAC#{SecureRandom.hex(2)}" }
    @project = Project.find_or_create_by!(name: "EA Test Project") { |p| p.status = "active"; p.client = @client }
  end

  def teardown
    EmployeeAssignment.where(employee: @employee).destroy_all
    @employee.destroy if Employee.exists?(@employee.id)
    @project.destroy if Project.exists?(@project.id) rescue nil
  end

  test "ASSIGNMENT_STATUSES 상수 정의됨" do
    assert_includes EmployeeAssignment::ASSIGNMENT_STATUSES, "active"
    assert_includes EmployeeAssignment::ASSIGNMENT_STATUSES, "completed"
    assert_includes EmployeeAssignment::ASSIGNMENT_STATUSES, "cancelled"
  end

  test "validates — 잘못된 status 거부 (write_attribute로 기본값 우회)" do
    ea = EmployeeAssignment.new(employee: @employee, project: @project, start_date: Date.today)
    ea.write_attribute(:status, "invalid_status")
    assert_not ea.valid?
    assert ea.errors[:status].present?
  end

  test "validates — 잘못된 status 값 거부" do
    ea = EmployeeAssignment.new(
      employee: @employee, project: @project,
      start_date: Date.today, status: "invalid"
    )
    assert_not ea.valid?
  end

  test "create — 유효한 배정 생성" do
    ea = EmployeeAssignment.create!(
      employee: @employee, project: @project,
      start_date: Date.today, status: "active"
    )
    assert ea.persisted?
  end

  test "status_label — 한글 레이블" do
    ea = EmployeeAssignment.new(status: "active")
    assert_equal "배정중", ea.status_label
    ea.status = "completed"
    assert_equal "완료", ea.status_label
    ea.status = "cancelled"
    assert_equal "취소", ea.status_label
  end

  test "scope active — active만 반환" do
    result = EmployeeAssignment.active
    assert result.is_a?(ActiveRecord::Relation)
    result.each { |ea| assert_equal "active", ea.status }
  end
end
