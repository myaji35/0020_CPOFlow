# frozen_string_literal: true

# Google Chat Incoming Webhook을 통한 알림 발송 서비스
# 설정: Rails.application.credentials.dig(:google_chat, :webhook_url)
class GoogleChatService
  def self.notify(message, order: nil, title: nil)
    new.notify(message, order: order, title: title)
  end

  def notify(message, order: nil, title: nil)
    webhook_url = Rails.application.credentials.dig(:google_chat, :webhook_url)
    return false unless webhook_url.present?

    payload = build_payload(message, order: order, title: title)
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

  def build_payload(message, order: nil, title: nil)
    if order.present?
      order_url = Rails.application.routes.url_helpers.order_url(
        order, host: Rails.application.credentials.dig(:app_host) || "localhost:3000"
      )
      {
        cards: [{
          header: {
            title: title || "CPOFlow 알림",
            subtitle: order.title,
            imageUrl: "https://fonts.gstatic.com/s/i/materialicons/notifications/v12/24px.svg"
          },
          sections: [{
            widgets: [
              {
                keyValue: {
                  topLabel: "상태",
                  content: Order::STATUS_LABELS[order.status] || order.status
                }
              },
              {
                keyValue: {
                  topLabel: "마감일",
                  content: order.due_date&.strftime("%Y-%m-%d") || "-"
                }
              },
              { textParagraph: { text: message } },
              {
                buttons: [{
                  textButton: {
                    text: "주문 상세 보기",
                    onClick: { openLink: { url: order_url } }
                  }
                }]
              }
            ]
          }]
        }]
      }
    else
      { text: "#{title ? "*#{title}*\n" : ""}#{message}" }
    end
  end
end
