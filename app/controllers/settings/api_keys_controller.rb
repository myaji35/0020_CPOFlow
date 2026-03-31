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
      token_status = ClaudeTokenResolver.status

      unless token_status[:configured]
        render json: { status: "error", message: "API Key가 설정되지 않았습니다." }
        return
      end

      source_label = { db: "DB", claude_cli: "Claude CLI", env: "환경변수", credentials: "credentials" }[token_status[:source]]

      begin
        client = ClaudeTokenResolver.create_client
        client.messages.create(
          model: "claude-haiku-4-5-20251001",
          max_tokens: 10,
          messages: [{ role: "user", content: "Say OK" }]
        )
        render json: { status: "ok", message: "API 연결 정상 — #{source_label} 토큰 사용 중 (#{token_status[:masked]})" }
      rescue => e
        error_msg = e.message.to_s
        if error_msg.include?("credit balance is too low")
          render json: { status: "error", message: "크레딧 잔액 부족 — Anthropic 콘솔에서 충전이 필요합니다." }
        elsif error_msg.include?("invalid x-api-key") || error_msg.include?("401") || error_msg.include?("403")
          render json: { status: "error", message: "유효하지 않은 토큰입니다 (#{source_label})." }
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
