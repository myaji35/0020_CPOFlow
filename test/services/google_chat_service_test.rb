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
    assert_includes [true, false], result
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

    order.destroy
    client.destroy
  end
end
