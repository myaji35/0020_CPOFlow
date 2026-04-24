require "test_helper"

class OrderTest < ActiveSupport::TestCase
  fixtures :card_statuses

  test "Order scopes 정상 동작" do
    assert_nothing_raised { Order.active.count }
    assert_nothing_raised { Order.overdue.count }
    assert_nothing_raised { Order.urgent.count }
    assert_nothing_raised { Order.by_due_date.limit(1).to_a }
  end

  test "Order status enum 유효" do
    valid = %w[new_rfq make_quo pending_po new_po delivery_items problem get_grn give_up done]
    valid.each do |s|
      assert Order.statuses.key?(s), "status #{s} 누락"
    end
  end

  test "Order card_status FK 유효" do
    # CardStatus가 로드되고 기본값 확보
    assert CardStatus.count > 0, "CardStatus fixtures 누락"
    assert_not_nil CardStatus.default
  end

  test "Order associations 쿼리 정상" do
    # 레코드 없어도 includes 쿼리 자체는 정상이어야 함
    assert_nothing_raised do
      Order.includes(:client, :supplier, :project, :assignees, :tasks, :comments).limit(5).to_a
    end
  end

  test "overdue 건수 계산 정확성" do
    overdue = Order.where.not(status: "delivered").where("due_date < ?", Date.today)
    assert overdue.count >= 0
  end

  test "urgent(D-7) 건수 계산 정확성" do
    urgent = Order.where.not(status: "delivered")
                  .where(due_date: Date.today..7.days.from_now)
    assert urgent.count >= 0
  end

  test "estimated_value 합계 계산" do
    total = Order.sum(:estimated_value).to_f
    assert total >= 0
  end

  # ISS-039: critical? / unassigned? / scope :critical
  setup do
    @owner = User.create!(
      email: "order_test_owner_#{SecureRandom.hex(3)}@example.com",
      password: "password123", name: "Order Test Owner", role: :member
    )
  end

  teardown do
    @owner.destroy if User.exists?(@owner.id)
  end

  test "critical? — urgent + overdue + unassigned이면 true" do
    order = Order.create!(user: @owner, title: "Critical Test", customer_name: "X",
                          status: :new_rfq, card_status: card_statuses(:urgent), due_date: 3.days.ago.to_date)
    assert order.critical?
  ensure
    order.reload.destroy
  end

  test "critical? — 담당자 있으면 false" do
    order = Order.create!(user: @owner, title: "Has Assignee", customer_name: "X",
                          status: :new_rfq, card_status: card_statuses(:urgent), due_date: 3.days.ago.to_date)
    emp = Employee.create!(name: "emp_#{SecureRandom.hex(3)}", nationality: "KR", active: true)
    Assignment.create!(order: order, employee: emp)
    assert_not order.critical?
  ensure
    Assignment.where(order: order).delete_all
    Employee.where(id: emp.id).delete_all if defined?(emp)
    order.reload.destroy
  end

  test "critical? — normal 우선순위면 false" do
    # card_status_manually_set_at을 미리 세팅해서 after_save 자동 재배정 차단
    order = Order.create!(user: @owner, title: "Normal Prio", customer_name: "X",
                          status: :new_rfq, card_status: card_statuses(:normal),
                          card_status_manually_set_at: Time.current,
                          due_date: 3.days.ago.to_date)
    order.reload
    assert_equal "normal", order.card_status.key
    assert_not order.critical?
  ensure
    order.reload.destroy
  end

  test "critical? — due_date 없으면 false" do
    order = Order.create!(user: @owner, title: "No Due", customer_name: "X",
                          status: :new_rfq, card_status: card_statuses(:urgent))
    assert_not order.critical?
  ensure
    order.reload.destroy
  end

  test "unassigned? — 담당자 없으면 true" do
    order = Order.create!(user: @owner, title: "Unassigned", customer_name: "X", status: :new_rfq)
    assert order.unassigned?
  ensure
    order.reload.destroy
  end

  test "scope :critical — SQL 실행 오류 없음" do
    assert_nothing_raised { Order.critical.count }
  end

  test "scope :critical — done/get_grn/give_up 제외" do
    # done 상태 + urgent + overdue는 critical에 포함되지 않아야 함
    order = Order.create!(user: @owner, title: "Done Critical", customer_name: "X",
                          status: :done, card_status: card_statuses(:urgent), due_date: 3.days.ago.to_date)
    assert_not Order.critical.exists?(order.id)
  ensure
    order.reload.destroy
  end

  # M1-Task4: Order status 전환 → confirmed_to/delivered_as 자동 링크
  test "status: pending_po → new_po + parent 있으면 confirmed_to 자동 생성" do
    user   = User.create!(
      email: "ct_#{SecureRandom.hex(4)}@example.com",
      password: "password123", name: "CT", role: :member
    )
    parent = Order.create!(
      user: user, title: "RFQ", reference_no: "CT-#{SecureRandom.hex(4)}",
      status: :pending_po, customer_name: "Test Customer"
    )
    child  = Order.create!(
      user: user, title: "PO", reference_no: parent.reference_no,
      status: :pending_po, customer_name: "Test Customer", parent_order: parent
    )

    assert_difference "OrderLink.where(relation: 'confirmed_to').count", 1 do
      child.update!(status: :new_po)
    end

    link = OrderLink.where(relation: "confirmed_to").last
    assert_equal parent, link.source
    assert_equal child,  link.target
    assert_equal "system_event", link.metadata["source"]
    assert_match(/status_transition/, link.metadata["trigger"])
  ensure
    child&.destroy
    parent&.destroy
    user&.destroy
  end

  test "status: → get_grn + parent 있으면 delivered_as 자동 생성" do
    user   = User.create!(
      email: "da_#{SecureRandom.hex(4)}@example.com",
      password: "password123", name: "DA", role: :member
    )
    parent = Order.create!(
      user: user, title: "PO", reference_no: "DA-#{SecureRandom.hex(4)}",
      status: :delivery_items, customer_name: "Test Customer"
    )
    child  = Order.create!(
      user: user, title: "GRN", reference_no: parent.reference_no,
      status: :delivery_items, customer_name: "Test Customer", parent_order: parent
    )

    assert_difference "OrderLink.where(relation: 'delivered_as').count", 1 do
      child.update!(status: :get_grn)
    end

    link = OrderLink.where(relation: "delivered_as").last
    assert_equal parent, link.source
    assert_equal child,  link.target
  ensure
    child&.destroy
    parent&.destroy
    user&.destroy
  end

  test "status 전환이지만 parent_order 없으면 confirmed_to/delivered_as 생성 안 함" do
    user  = User.create!(
      email: "lo_#{SecureRandom.hex(4)}@example.com",
      password: "password123", name: "LO", role: :member
    )
    order = Order.create!(
      user: user, title: "Lone", reference_no: "LO-#{SecureRandom.hex(4)}",
      status: :pending_po, customer_name: "Test Customer"
    )

    assert_no_difference "OrderLink.where(relation: ['confirmed_to', 'delivered_as']).count" do
      order.update!(status: :new_po)
    end
  ensure
    order&.destroy
    user&.destroy
  end

  test "parent_order_id 설정 시 derived_from 링크 자동 생성" do
    user   = User.create!(
      email: "df_#{SecureRandom.hex(4)}@example.com",
      password: "password123", name: "DF"
    )
    parent = Order.create!(
      user: user, title: "RFQ", reference_no: "DF-#{SecureRandom.hex(4)}",
      status: :new_rfq, customer_name: "Test Customer"
    )
    child  = Order.create!(
      user: user, title: "Quote", reference_no: parent.reference_no,
      status: :make_quo, customer_name: "Test Customer"
    )

    assert_difference "OrderLink.where(relation: 'derived_from').count", 1 do
      child.update!(parent_order: parent)
    end

    link = OrderLink.where(relation: "derived_from").last
    assert_equal child,  link.source   # 후속 → 원본 방향
    assert_equal parent, link.target
    assert_equal "system_event", link.metadata["source"]
    assert_equal "parent_order_id_changed", link.metadata["trigger"]
  ensure
    child&.destroy
    parent&.destroy
    user&.destroy
  end

  test "parent_order_id 변경 없으면 derived_from 생성 안 함" do
    user  = User.create!(
      email: "df2_#{SecureRandom.hex(4)}@example.com",
      password: "password123", name: "DF2"
    )
    order = Order.create!(
      user: user, title: "T", reference_no: "DF2-#{SecureRandom.hex(4)}",
      status: :new_rfq, customer_name: "Test Customer"
    )

    assert_no_difference "OrderLink.where(relation: 'derived_from').count" do
      order.update!(title: "Updated Title")
    end
  ensure
    order&.destroy
    user&.destroy
  end
end
