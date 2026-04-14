# frozen_string_literal: true

require "test_helper"

class AssignmentTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "assignment_test@example.com") do |u|
      u.name = "Assignment Tester"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "Assign Test Supplier") do |s|
      s.code = "ASST#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "Assignment Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          @user,
      supplier:      @supplier
    )
  end

  def teardown
    Assignment.where(order: @order).destroy_all
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "create — user 배정 생성" do
    assignment = Assignment.create!(order: @order, user: @user)
    assert assignment.persisted?
    assignment.destroy
  end

  test "belongs_to order" do
    assignment = Assignment.create!(order: @order, user: @user)
    assert_equal @order, assignment.order
    assignment.destroy
  end

  test "validates — order+employee 유일성 (duplicate rejected)" do
    employee = Employee.create!(
      name: "Assign Emp #{SecureRandom.hex(3)}", nationality: "KR",
      employment_type: "regular"
    )
    Assignment.create!(order: @order, employee: employee)
    dup = Assignment.new(order: @order, employee: employee)
    assert_not dup.valid?
    employee.destroy
  end
end
