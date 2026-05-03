# frozen_string_literal: true

require "test_helper"

class AutoAssignerServiceTest < ActiveSupport::TestCase
  fixtures :card_statuses

  # ── 픽스처 헬퍼 ─────────────────────────────────────────────────────
  def create_user(attrs = {})
    User.create!(
      { name: "Test User #{rand(9999)}", email: "user#{rand(99999)}@test.com",
        password: "password123", role: :member, branch: :abu_dhabi }.merge(attrs)
    )
  end

  def create_order(attrs = {})
    cs = CardStatus.default || CardStatus.create!(key: "normal", label: "Normal", bg_color: "#fff", border_color: "#ccc", text_color: "#000")
    user = create_user(role: :admin)
    Order.create!(
      { title: "Test Order #{rand(9999)}", customer_name: "TestCo",
        status: :new_rfq, user: user, card_status: cs }.merge(attrs)
    )
  end

  def create_client(attrs = {})
    Client.create!(
      { name: "Test Client #{rand(9999)}", code: "CL#{rand(9999)}",
        country: "AE" }.merge(attrs)
    )
  end

  def create_supplier(attrs = {})
    Supplier.create!({ name: "Test Supplier #{rand(9999)}" }.merge(attrs))
  end

  # ── 테스트 케이스 ────────────────────────────────────────────────────
  test "이미 배정된 Order는 스킵" do
    order = create_order
    # after_create_commit으로 이미 배정됐을 수 있음 — count 기억 후 재실행 확인
    count_before = order.assignments.count

    result = AutoAssignerService.new(order).call
    assert_nil result, "이미 배정된 경우 nil 반환해야 함"
    assert_equal count_before, order.assignments.reload.count, "Assignment 레코드가 추가되지 않아야 함"
  end

  test "client.default_assignee_id로 배정" do
    assignee = create_user
    client = create_client(default_assignee_id: assignee.id)
    order = create_order(client: client)
    # after_create_commit으로 이미 배정됐을 수 있으므로 assignments 초기화 후 재테스트
    order.assignments.delete_all

    result = AutoAssignerService.new(order).call
    assert_equal assignee.id, result
    assert order.assignments.where(user_id: assignee.id).exists?
  end

  test "client 없을 때 supplier.default_assignee_id로 배정" do
    assignee = create_user
    supplier = Supplier.create!(name: "TestSup#{rand(9999)}", default_assignee_id: assignee.id)
    order = create_order(client: nil, supplier: supplier)
    order.assignments.delete_all

    result = AutoAssignerService.new(order).call
    assert_equal assignee.id, result
  end

  test "client/supplier default_assignee 없을 때 branch admin으로 배정" do
    creator = create_user(role: :member, branch: :abu_dhabi)
    admin   = create_user(role: :admin, branch: :abu_dhabi)
    cs      = CardStatus.default
    order   = Order.create!(
      title: "Branch Test #{rand(9999)}", customer_name: "TestCo",
      status: :new_rfq, user: creator, card_status: cs
    )
    order.assignments.delete_all

    result = AutoAssignerService.new(order).call
    assert_not_nil result
    assert_equal admin.id, result
  end

  test "아무것도 없으면 nil 반환" do
    # branch에 admin이 없어야 nil — seoul branch에 admin 없는 상황
    creator = create_user(role: :member, branch: :seoul)
    User.where(role: :admin, branch: :seoul).update_all(role: :viewer)
    cs    = CardStatus.default
    order = Order.create!(
      title: "No Assignee Test #{rand(9999)}", customer_name: "TestCo",
      status: :new_rfq, user: creator, card_status: cs, client_id: nil
    )
    order.assignments.delete_all

    result = AutoAssignerService.new(order).call
    assert_nil result
  end

  test "신규 Order 생성 시 after_create_commit으로 자동 배정 시도" do
    creator = create_user(role: :member, branch: :abu_dhabi)
    admin   = create_user(role: :admin, branch: :abu_dhabi)
    cs      = CardStatus.default

    order = Order.create!(
      title: "Auto Assign Test #{rand(9999)}", customer_name: "TestCo",
      status: :new_rfq, user: creator, card_status: cs
    )

    # after_create_commit이 실행됐으면 assignment 존재
    order.reload
    assert order.assignments.exists?, "신규 Order 생성 시 자동 배정돼야 함"
  end
end
