# frozen_string_literal: true

module Admin
  class SheetsConfigController < ApplicationController
    before_action :require_admin!

    def update
      url = params[:spreadsheet_url].to_s.strip
      id  = AppConfig.extract_spreadsheet_id(url)

      if id.present?
        AppConfig.set(
          AppConfig::SHEETS_SPREADSHEET_ID,
          id,
          description: "Google Sheets Spreadsheet ID (admin 설정)"
        )
        AppConfig.set(
          AppConfig::SHEETS_SPREADSHEET_URL,
          url,
          description: "Google Sheets URL (admin 입력값)"
        )
        redirect_to settings_root_path,
                    notice: "Google Sheets 연동이 저장되었습니다. (ID: #{id[..12]}...)"
      else
        redirect_to settings_root_path,
                    alert: "올바른 Google Sheets URL을 입력해주세요."
      end
    end

    def clear
      AppConfig.where(key: [
        AppConfig::SHEETS_SPREADSHEET_ID,
        AppConfig::SHEETS_SPREADSHEET_URL
      ]).destroy_all
      redirect_to settings_root_path, notice: "Google Sheets 연동 설정이 초기화되었습니다."
    end

    private

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근 가능합니다." unless current_user.admin?
    end
  end
end
