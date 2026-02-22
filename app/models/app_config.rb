# frozen_string_literal: true

# 앱 전역 설정 저장소 (key-value)
# Admin 전용으로 관리되며, credentials 보다 우선 적용됩니다.
#
# 사용 예:
#   AppConfig.get("google_sheets_spreadsheet_id")
#   AppConfig.set("google_sheets_spreadsheet_id", "1BxiM...")
class AppConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Google Sheets 관련 키
  SHEETS_SPREADSHEET_ID  = "google_sheets_spreadsheet_id"
  SHEETS_SPREADSHEET_URL = "google_sheets_spreadsheet_url"
  SHEETS_ENABLED         = "google_sheets_enabled"

  class << self
    def get(key)
      find_by(key: key)&.value
    end

    def set(key, value, description: nil)
      record = find_or_initialize_by(key: key)
      record.value       = value
      record.description = description if description.present?
      record.save!
      record
    end

    def sheets_spreadsheet_id
      get(SHEETS_SPREADSHEET_ID).presence ||
        Rails.application.credentials.dig(:google, :sheets_spreadsheet_id)
    end

    def sheets_spreadsheet_url
      get(SHEETS_SPREADSHEET_URL)
    end

    def sheets_enabled?
      get(SHEETS_ENABLED) != "false"
    end
  end

  # URL에서 Spreadsheet ID 자동 추출
  # https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
  def self.extract_spreadsheet_id(url)
    return url if url.blank?
    url.match(%r{/spreadsheets/d/([a-zA-Z0-9_-]+)})&.captures&.first || url
  end
end
