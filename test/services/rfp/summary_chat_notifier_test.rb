require "test_helper"

class Rfp::SummaryChatNotifierTest < ActiveSupport::TestCase
  def setup
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
    @user = User.create!(name: "Notifier User", email: "notifier-#{SecureRandom.hex(4)}@test.local", password: "password123")
    @order = Order.create!(title: "Notifier RFQ", customer_name: "Test Client", user: @user, status: :new_rfq)
    @report = {
      markdown_ko: "마감일: 2026-08-01\n품목 수: 1\n\n| # | 품목 | 모델 | 사양 | 수량 | 단위 | 납기 | 인증 |\n|---:|---|---|---|---:|---|---|---|\n| 1 | Valve | - | - | 2 | EA | - | - |",
      summary_en: "Procure two valves.",
      items: [{ name: "Valve", quantity: 2, unit: "EA" }],
      deadline: "2026-08-01"
    }
  end

  teardown do
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
  end

  test "webhook URL 미설정 시 false를 반환하고 HTTP를 호출하지 않는다" do
    without_http_calls do
      assert_equal false, Rfp::SummaryChatNotifier.call(@order, @report)
    end
  end

  test "당일 중복 발송은 skip한다" do
    AppSetting.set("google_chat_webhook_url", "https://chat.example.com/webhook")
    Notification.create!(user: @user, notifiable: @order, notification_type: "rfp_summary_report", title: "sent", body: "sent")

    without_http_calls do
      assert_equal false, Rfp::SummaryChatNotifier.call(@order, @report)
    end
  end

  test "품목명에 파이프가 포함돼도 품목 수가 정확하다" do
    AppSetting.set("google_chat_webhook_url", "https://chat.example.com/webhook")
    @report[:items] = [{ name: "A|B Valve", quantity: 2, unit: "EA" }]
    payload = nil
    original = Net::HTTP.method(:post)
    Net::HTTP.define_singleton_method(:post) do |_uri, body, _headers|
      payload = JSON.parse(body)
    end

    assert Rfp::SummaryChatNotifier.call(@order, @report)
    assert_includes payload["text"], "A|B Valve"
    assert_equal "품목 1건 분석 완료", Notification.find_by!(
      notifiable: @order,
      notification_type: "rfp_summary_report"
    ).body
  ensure
    Net::HTTP.define_singleton_method(:post, original) if original
  end

  private

  def without_http_calls
    original = Net::HTTP.method(:post)
    Net::HTTP.define_singleton_method(:post) { |*| raise "HTTP should not be called" }
    yield
  ensure
    Net::HTTP.define_singleton_method(:post, original)
  end
end
