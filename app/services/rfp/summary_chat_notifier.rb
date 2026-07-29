module Rfp
  class SummaryChatNotifier
    def self.call(order, report)
      new(order, report).call
    end

    def initialize(order, report)
      @order = order
      @report = report
    end

    def call
      require "net/http"
      require "uri"

      url = AppSetting.google_chat_webhook_url
      if url.blank?
        Rails.logger.info("[Rfp::SummaryChatNotifier] webhook URL 없음, skip")
        return false
      end
      return false if already_sent_today?

      Net::HTTP.post(URI(url), { text: message_text }.to_json, "Content-Type" => "application/json")
      create_notifications
      true
    rescue => e
      Rails.logger.error("[Rfp::SummaryChatNotifier] chat notification failed: #{e.class}: #{e.message}")
      false
    end

    private

    def already_sent_today?
      Notification.where(
        notifiable: @order,
        notification_type: "rfp_summary_report"
      ).where("created_at >= ?", Date.current.beginning_of_day).exists?
    end

    def message_text
      items = @report[:items] || []
      item_lines = items.filter_map do |item|
        next if item[:name].blank?

        quantity = item[:quantity].present? ? " x#{item[:quantity]}#{item[:unit]}" : ""
        "• #{item[:name]}#{quantity}"
      end
      item_lines = item_lines.first(5)
      item_lines << "…외 #{items.size - 5}건" if items.size > 5

      [
        "📋 *RFP 분석 요약* — #{@order.title.to_s.first(60)}",
        "발주처: #{@order.client&.name || '-'}",
        "마감: #{@report[:deadline].presence || '-'}",
        "품목: #{items.size}건",
        *item_lines,
        "",
        "[EN] #{@report[:summary_en].to_s.first(300)}",
        "",
        "<https://cpoflow.ddtl.co.kr/orders/#{@order.id}|카드 보기>"
      ].join("\n")
    end

    def create_notifications
      recipients.each do |user|
        Notification.create!(
          user: user,
          notifiable: @order,
          notification_type: "rfp_summary_report",
          title: "📋 RFP 분석 요약: #{@order.title.to_s.first(40)}",
          body: "품목 #{(@report[:items] || []).size}건 분석 완료"
        )
      end
    end

    def recipients
      users = []
      users << @order.user
      users += @order.assignments.includes(:user).map(&:user).compact
      users += User.where(role: %w[admin manager])
      users.compact.uniq
    end
  end
end
