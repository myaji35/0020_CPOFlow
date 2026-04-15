# frozen_string_literal: true

require "test_helper"

class OrderMailerTest < ActionMailer::TestCase
  def setup
    @user = User.find_or_create_by!(email: "mailer_test@example.com") do |u|
      u.name = "Mailer Test User"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "Mailer Test Supplier") { |s| s.code = "MLTS#{SecureRandom.hex(2)}" }
    @order = Order.create!(
      title:         "Mailer Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          @user,
      supplier:      @supplier,
      due_date:      7.days.from_now.to_date
    )
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "due_reminder — 메일 생성됨" do
    mail = OrderMailer.due_reminder(@order, @user, 7)
    assert_not_nil mail
  end

  test "due_reminder — 수신자 확인" do
    mail = OrderMailer.due_reminder(@order, @user, 7)
    assert_equal [@user.email], mail.to
  end

  test "due_reminder — 제목에 Action Required 포함 (D-7)" do
    mail = OrderMailer.due_reminder(@order, @user, 7)
    assert_includes mail.subject, "Action Required"
  end

  test "due_reminder — 제목에 Reminder 포함 (D-14 이후)" do
    mail = OrderMailer.due_reminder(@order, @user, 15)
    assert_includes mail.subject, "Reminder"
  end

  test "due_reminder — D-0 시 OVERDUE TODAY 제목" do
    mail = OrderMailer.due_reminder(@order, @user, 0)
    assert_includes mail.subject, "OVERDUE TODAY"
  end

  test "due_reminder — D-3 시 URGENT 제목" do
    mail = OrderMailer.due_reminder(@order, @user, 3)
    assert_includes mail.subject, "URGENT"
  end

  test "due_reminder — D-1 시 tomorrow 날짜 표현" do
    mail = OrderMailer.due_reminder(@order, @user, 1)
    assert_includes mail.subject, "tomorrow"
  end
end
