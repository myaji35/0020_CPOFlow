# frozen_string_literal: true

# Google Chat Incoming Webhook을 통한 알림 발송 서비스
# Webhook URL: AppSetting.google_chat_webhook_url (DB 저장)
class GoogleChatService
  # D-14 → blue, D-7 → orange, D-3/D-0 → red
  URGENCY_COLOR = {
    14 => "#1E88E5",
    7  => "#F4A83A",
    3  => "#D93025",
    0  => "#B71C1C"
  }.freeze

  def self.notify(message, order: nil, title: nil, days_ahead: nil)
    new.notify(message, order: order, title: title, days_ahead: days_ahead)
  end

  def notify(message, order: nil, title: nil, days_ahead: nil)
    webhook_url = AppSetting.google_chat_webhook_url ||
                  Rails.application.credentials.dig(:google_chat, :webhook_url)
    return false unless webhook_url.present?

    payload = build_payload(message, order: order, title: title, days_ahead: days_ahead)
    response = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = payload.to_json
    end

    response.success?
  rescue => e
    Rails.logger.error "[GoogleChatService] #{e.class}: #{e.message}"
    false
  end

  private

  def build_payload(message, order: nil, title: nil, days_ahead: nil)
    if order.present?
      build_order_card(message, order: order, title: title, days_ahead: days_ahead)
    else
      { text: "#{title ? "*#{title}*\n" : ""}#{message}" }
    end
  end

  def build_order_card(message, order:, title:, days_ahead:)
    color   = URGENCY_COLOR[days_ahead] || "#1E3A5F"
    app_host = Rails.application.credentials.dig(:app_host) || "localhost:3000"
    order_url = Rails.application.routes.url_helpers.order_url(order, host: app_host)

    urgency_label = case days_ahead
    when 0  then "🔴 오늘 납기!"
    when 3  then "🟠 D-3 긴급"
    when 7  then "🟡 D-7 주의"
    when 14 then "🔵 D-14 예고"
    else "납기 알림"
    end

    {
      cards: [ {
        header: {
          title: title || urgency_label,
          subtitle: order.title.truncate(60),
          imageUrl: "https://www.gstatic.com/images/icons/material/system/1x/notifications_black_48dp.png"
        },
        sections: [ {
          widgets: [
            {
              keyValue: {
                topLabel: "발주처",
                content: order.client&.name || order.customer_name || "-"
              }
            },
            {
              keyValue: {
                topLabel: "납기일",
                content: order.due_date&.strftime("%Y-%m-%d (%a)") || "-",
                contentMultiline: false
              }
            },
            {
              keyValue: {
                topLabel: "상태",
                content: Order::STATUS_LABELS[order.status] || order.status
              }
            },
            {
              keyValue: {
                topLabel: "담당자",
                content: order.assignees.map(&:display_name).join(", ").presence || "-"
              }
            },
            { textParagraph: { text: "<font color=\"#{color}\"><b>#{message}</b></font>" } },
            {
              buttons: [ {
                textButton: {
                  text: "주문 상세 보기",
                  onClick: { openLink: { url: order_url } }
                }
              } ]
            }
          ]
        } ]
      } ]
    }
  end
end
