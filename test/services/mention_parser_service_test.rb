# frozen_string_literal: true

require "test_helper"

class MentionParserServiceTest < ActiveSupport::TestCase
  def setup
    @mentioner = User.find_or_create_by(email: "mention_mentioner@example.com") do |u|
      u.name = "Mention Mentioner"; u.password = "password123"; u.role = :member
    end
    @mentioned_user = User.find_or_create_by(email: "mention_target@example.com") do |u|
      u.name = "Mention Target"; u.password = "password123"; u.role = :member
    end
    @employee = Employee.find_or_create_by(name: "홍길동멘션테스트") do |e|
      e.nationality = "KR"; e.employment_type = "regular"
    end
    @employee.update!(user_id: @mentioned_user.id)
    @order = Order.create!(title: "Mention Test Order", customer_name: "Cust", user: @mentioner, status: :new_rfq)
    @comment = Comment.create!(body: "테스트 코멘트", order: @order, user: @mentioner)
  end

  def teardown
    @comment.destroy if Comment.exists?(@comment.id)
    @order.destroy if Order.exists?(@order.id)
  end

  test "멘션 없으면 Notification 미생성" do
    @comment.update!(body: "멘션 없는 일반 코멘트")
    assert_no_difference("Notification.count") do
      MentionParserService.new(@comment, @mentioner).call
    end
  end

  test "@이름 멘션 시 해당 유저에게 Notification 생성" do
    @comment.update!(body: "@홍길동멘션테스트, 확인 부탁드립니다")
    assert_difference("Notification.count", 1) do
      MentionParserService.new(@comment, @mentioner).call
    end
    notif = Notification.order(created_at: :desc).first
    assert_equal @mentioned_user, notif.user
    assert_equal "mentioned", notif.notification_type
    Notification.order(created_at: :desc).first.destroy
  end

  test "자기 자신 멘션은 Notification 미생성" do
    # mentioner 본인이 employee로 등록된 경우
    self_employee = Employee.find_or_create_by(name: "셀프멘션테스트유저") do |e|
      e.nationality = "KR"; e.employment_type = "regular"; e.user_id = @mentioner.id
    end
    @comment.update!(body: "@셀프멘션테스트유저 셀프 멘션")
    assert_no_difference("Notification.count") do
      MentionParserService.new(@comment, @mentioner).call
    end
    self_employee.destroy
  end

  test "매칭 Employee 없으면 Notification 미생성" do
    @comment.update!(body: "@존재하지않는사람 확인 요청")
    assert_no_difference("Notification.count") do
      MentionParserService.new(@comment, @mentioner).call
    end
  end

  test "employee에 user_id 없으면 Notification 미생성" do
    no_user_emp = Employee.create!(name: "유저없는직원멘션테스트", nationality: "KR", employment_type: "regular")
    @comment.update!(body: "@유저없는직원멘션테스트 확인")
    assert_no_difference("Notification.count") do
      MentionParserService.new(@comment, @mentioner).call
    end
    no_user_emp.destroy
  end
end
