# frozen_string_literal: true

require "test_helper"

class OverdueEscalationJobTest < ActiveJob::TestCase
  # test_helper.rb 의 `fixtures :all` 이 주석 처리돼 있어 각 테스트가 필요한
  # fixture를 개별 선언한다(order_test.rb 등 다른 테스트의 기존 패턴).
  # 이 선언이 없어 CardStatus.find_by!(key: "urgent") 가 RecordNotFound로 죽었다.
  fixtures :card_statuses

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
      card_status:   CardStatus.find_by!(key: "urgent"),
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

  # ISS-410: AutoAssignerService가 만드는 user-only Assignment(employee_id: nil)는
  # '실담당 직원 배정'이 아니다. 이걸 배정으로 취급하면 admin이 있는 지점의 모든
  # 신규 주문에서 escalation이 영구히 발화하지 않는다.
  test "user만 배정된 Assignment는 미배정으로 보고 escalation 발화" do
    # AutoAssignerService(after_create_commit)가 이미 user-only Assignment를 만들어 둔다.
    # 없는 환경(admin 부재 등)에서도 조건을 동일하게 맞춘다.
    Assignment.find_or_create_by!(order: @critical_order, employee_id: nil) do |a|
      a.user = @owner
      a.role = "auto"
    end
    assert Assignment.where(order: @critical_order, employee_id: nil).exists?

    assert @critical_order.reload.critical?, "employee 미배정이므로 critical이어야 함"
    assert_includes Order.critical.pluck(:id), @critical_order.id,
                    "critical 스코프도 critical?와 동일하게 판정해야 함"

    assert_difference "Notification.count", 1 do
      OverdueEscalationJob.perform_now
    end
  ensure
    Assignment.where(order: @critical_order).delete_all
  end
end
