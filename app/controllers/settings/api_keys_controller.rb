# frozen_string_literal: true

module Settings
  class ApiKeysController < ApplicationController
    before_action :require_admin

    def update
      key = params[:anthropic_api_key].to_s.strip

      if key.present?
        AppSetting.set("anthropic_api_key", key)
        redirect_to settings_root_path(anchor: "api-keys"), notice: "Anthropic API Key가 저장되었습니다."
      else
        AppSetting.find_by(key: "anthropic_api_key")&.destroy
        redirect_to settings_root_path(anchor: "api-keys"), notice: "Anthropic API Key가 삭제되었습니다."
      end
    end

    def verify
      api_key = AppSetting.get("anthropic_api_key").presence ||
                Rails.application.credentials.dig(:anthropic, :api_key)

      if api_key.blank?
        render json: { status: "error", message: "API Key가 설정되지 않았습니다." }
        return
      end

      begin
        client = Anthropic::Client.new(api_key: api_key)
        response = client.messages.create(
          model: "claude-haiku-4-5-20251001",
          max_tokens: 10,
          messages: [{ role: "user", content: "Say OK" }]
        )
        render json: { status: "ok", message: "API 연결 정상 — 크레딧 사용 가능" }
      rescue => e
        error_msg = e.message.to_s
        if error_msg.include?("credit balance is too low")
          render json: { status: "error", message: "크레딧 잔액 부족 — Anthropic 콘솔에서 충전이 필요합니다." }
        elsif error_msg.include?("invalid x-api-key") || error_msg.include?("401")
          render json: { status: "error", message: "유효하지 않은 API Key입니다." }
        else
          render json: { status: "error", message: "연결 오류: #{error_msg[0..100]}" }
        end
      end
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "관리자만 접근 가능합니다."
      end
    end
  end
end
