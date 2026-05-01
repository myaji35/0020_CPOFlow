# frozen_string_literal: true

require "test_helper"

class GoogleChatServiceTest < ActiveSupport::TestCase
  def setup
    # Webhook URL 미설정 상태로 격리
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
  end

  def teardown
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
  end

  test "notify — webhook URL 없으면 false 반환" do
    result = GoogleChatService.notify("테스트 메시지")
    assert_equal false, result
  end

  test "notify — 클래스 메서드로 호출 가능" do
    result = GoogleChatService.notify("테스트", title: "제목")
    assert_includes [ true, false ], result
  end

  test "notify — order 파라미터 있어도 오류 없음" do
    user = User.find_or_create_by(email: "gchat_test@example.com") do |u|
      u.name = "GChat Test"; u.password = "password123"; u.role = :member
    end
    client = Client.create!(name: "GChat Test Client", code: "GCHAT#{SecureRandom.hex(3)}")
    order = Order.create!(title: "GChat 테스트", customer_name: "Test", client: client, status: :new_rfq, user: user)

    assert_nothing_raised do
      GoogleChatService.notify("주문 알림", order: order, days_ahead: 7)
    end

    order.reload.destroy
    client.destroy
  end

  test "build_payload — order 없으면 text hash 반환" do
    svc = GoogleChatService.new
    result = svc.send(:build_payload, "Hello", title: "알림", order: nil)
    assert_equal "*알림*\nHello", result[:text]
  end

  test "build_payload — title 없으면 텍스트만" do
    svc = GoogleChatService.new
    result = svc.send(:build_payload, "Simple message", order: nil)
    assert_equal "Simple message", result[:text]
  end

  test "build_payload — order 있으면 cards 구조 반환" do
    user = User.find_or_create_by!(email: "gchat_card_test@example.com") do |u|
      u.name = "GChat Card"; u.password = "password123"; u.role = :member
    end
    client = Client.create!(name: "GChat Card Client", code: "GCARDCL#{SecureRandom.hex(2)}")
    order = Order.create!(title: "GChat Card Test", customer_name: "Card Customer",
                          client: client, status: :new_rfq, user: user,
                          due_date: 7.days.from_now.to_date)
    svc = GoogleChatService.new
    result = svc.send(:build_payload, "납기 알림", order: order, days_ahead: 7, title: "D-7 주의")
    assert result[:cards].present?
    order.destroy; client.destroy
  end

  test "build_order_card — D-0 색상 설정" do
    user = User.find_or_create_by!(email: "gchat_d0_test@example.com") do |u|
      u.name = "GChat D0"; u.password = "password123"; u.role = :member
    end
    order = Order.create!(title: "GChat D0 Test", customer_name: "D0 Customer",
                          status: :new_rfq, user: user, due_date: Date.today)
    svc = GoogleChatService.new
    result = svc.send(:build_order_card, "오늘 납기!", order: order, title: nil, days_ahead: 0)
    assert result[:cards].present?
    order.reload.destroy
  end

  test "URGENCY_COLOR 상수 정의됨" do
    assert_kind_of Hash, GoogleChatService::URGENCY_COLOR
  end
end
