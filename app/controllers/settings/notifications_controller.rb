# frozen_string_literal: true

module Settings
  class NotificationsController < ApplicationController
    before_action :authorize_admin!

    def update
      AppSetting.set("google_chat_webhook_url", params[:google_chat_webhook_url].to_s.strip)
      redirect_to settings_root_path, notice: "Google Chat Webhook URL이 저장되었습니다."
    end

    def test
      url = AppSetting.google_chat_webhook_url
      if url.blank?
        redirect_to settings_root_path, alert: "Webhook URL을 먼저 저장해 주세요."
        return
      end

      success = GoogleChatService.notify(
        "✅ CPOFlow 연결 테스트 메시지입니다. 알림이 정상 작동합니다.",
        title: "CPOFlow 테스트 알림"
      )

      if success
        redirect_to settings_root_path, notice: "Google Chat 테스트 메시지를 발송했습니다."
      else
        redirect_to settings_root_path, alert: "Google Chat 발송에 실패했습니다. Webhook URL을 확인해 주세요."
      end
    end

    private

    def authorize_admin!
      redirect_to root_path, alert: "권한이 없습니다." unless current_user.admin? || current_user.manager?
    end
  end
end
