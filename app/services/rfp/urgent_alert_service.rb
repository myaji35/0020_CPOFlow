# ISS-328: RFP 마감 D-1 긴급 알림 서비스
# AnalyzeAttachmentsJob이 deadline 추출 후 D-1 이내일 때 호출
module Rfp
  class UrgentAlertService
    def self.call(order, deadline_date, days_left)
      new(order, deadline_date, days_left).call
    end

    def initialize(order, deadline_date, days_left)
      @order = order
      @deadline_date = deadline_date
      @days_left = days_left
    end

    def call
      return if already_alerted_today?

      set_urgent_card_status
      create_notifications
      send_gchat_alert if AppSetting.google_chat_webhook_url.present?
      record_activity
    rescue => e
      Rails.logger.error("[Rfp::UrgentAlertService] order=#{@order.id} #{e.class}: #{e.message}")
    end

    private

    # 당일 이미 동일 order에 rfp_urgent 알림이 발송됐으면 skip
    def already_alerted_today?
      Notification.where(
        notifiable: @order,
        notification_type: "rfp_urgent_d#{@days_left}"
      ).where("created_at >= ?", Date.current.beginning_of_day).exists?
    end

    def set_urgent_card_status
      # 수동 지정된 경우 자동 덮어쓰기 금지
      return if @order.card_status_manually_set_at.present?

      urgent_status = CardStatus.find_by(key: "urgent") || CardStatus.find_by(key: "critical")
      return unless urgent_status

      if @order.card_status_id != urgent_status.id
        @order.update_columns(card_status_id: urgent_status.id)
        Rails.logger.info("[Rfp::UrgentAlertService] order=#{@order.id} → card_status=#{urgent_status.key}")
      end
    end

    def create_notifications
      recipients.each do |user|
        Notification.create!(
          user: user,
          notifiable: @order,
          notification_type: "rfp_urgent_d#{@days_left}",
          title: "🚨 마감 D-#{@days_left}: #{@order.title.to_s.first(40)}",
          body: "#{@deadline_date.strftime('%Y-%m-%d')} 마감 — 즉시 견적 작성 필요"
        )
      end
    end

    def send_gchat_alert
      require "net/http"
      require "uri"

      url = AppSetting.google_chat_webhook_url
      label = @days_left.zero? ? "오늘 마감" : "D-#{@days_left}"
      payload = {
        text: "🚨 *RFP 마감 #{label}* — #{@order.title.to_s.first(60)}\n" \
              "마감: #{@deadline_date.strftime('%Y-%m-%d')}\n" \
              "담당: #{assignee_names}\n" \
              "<https://cpoflow.ddtl.co.kr/orders/#{@order.id}|카드 보기>"
      }
      Net::HTTP.post(URI(url), payload.to_json, "Content-Type" => "application/json")
    rescue => e
      Rails.logger.error("[Rfp::UrgentAlertService] gchat fail: #{e.message}")
    end

    def record_activity
      admin_user = User.where(role: :admin).first
      return unless admin_user

      Activity.create!(
        order: @order,
        user: admin_user,
        action: "rfp_urgent_alert",
        old_value: nil,
        new_value: "D-#{@days_left} 마감 알림 발송 (#{@deadline_date})"
      )
    end

    def recipients
      users = []
      users << @order.user
      users += @order.assignments.includes(:user).map(&:user).compact
      users += User.where(role: %w[admin manager])
      users.compact.uniq
    end

    def assignee_names
      names = @order.assignees.map(&:name)
      names.any? ? names.join(", ") : "미배정"
    end
  end
end
