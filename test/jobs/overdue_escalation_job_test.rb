# frozen_string_literal: true

require "test_helper"

class OverdueEscalationJobTest < ActiveJob::TestCase
  HEX = -> { SecureRandom.hex(4) }

  setup do
    @admin = User.create!(
      email: "esc_admin_#{HEX.call}@example.com",
      password: "password123", name: "Esc Admin",
      role: :admin, branch: :abu_dhabi
    )
    @owner = User.create!(
      email: "esc_owner_#{HEX.call}@example.com",
      password: "password123", name: "Esc Owner",
      role: :member, branch: :abu_dhabi
    )
    @critical_order = Order.create!(
      user:          @owner,
      title:         "긴급 담당자 없는 발주",
      customer_name: "Test Client",
      status:        :new_rfq,
      priority:      :urgent,
      due_date:      5.days.ago.to_date
    )
    # 기존 escalation 알림 클린업 (멱등성 테스트를 위해)
    Notification.where(
      notifiable:        @critical_order,
      notification_type: OverdueEscalationJob::ESCALATION_TYPE
    ).delete_all
  end

  teardown do
    Notification.where(notifiable: @critical_order).delete_all
    @critical_order.destroy if Order.exists?(@critical_order.id)
    @owner.destroy     if User.exists?(@owner.id)
    @admin.destroy     if User.exists?(@admin.id)
  end

  test "critical Order에 대해 admin에게 Notification 생성" do
    assert_difference "Notification.count", 1 do
      OverdueEscalationJob.perform_now
    end
    n = Notification.where(notifiable: @critical_order, notification_type: OverdueEscalationJob::ESCALATION_TYPE).last
    assert_not_nil n, "escalation Notification이 생성돼야 함"
    assert_equal @admin, n.user
    assert_includes n.body, "담당자 미배정"
  end

  test "같은 날 재실행 시 중복 생성 안 함 (멱등성)" do
    OverdueEscalationJob.perform_now
    assert_no_difference "Notification.count" do
      OverdueEscalationJob.perform_now
    end
  end

  test "담당자가 배정된 Order는 escalation skip" do
    # Employee 생성 후 assignment
    employee = Employee.create!(name: "담당직원_#{HEX.call}", nationality: "KR", active: true)
    Assignment.create!(order: @critical_order, employee: employee)

    # 이제 @critical_order.critical? == false (담당자 있음)
    assert_no_difference "Notification.count" do
      OverdueEscalationJob.perform_now
    end
  ensure
    Assignment.where(order: @critical_order).delete_all
    Employee.where(id: employee.id).delete_all if defined?(employee)
  end
end
