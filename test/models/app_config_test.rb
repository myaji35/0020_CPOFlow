require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  test "get: 존재하지 않는 key이면 nil 반환" do
    result = AppConfig.get("nonexistent_key_#{SecureRandom.hex(4)}")
    assert_nil result
  end

  test "sheets_enabled?: false 문자열이 아니면 true" do
    # DB에 해당 키가 없으면 기본적으로 true
    AppConfig.where(key: AppConfig::SHEETS_ENABLED).delete_all
    assert AppConfig.sheets_enabled?
  end

  test "extract_spreadsheet_id: nil이면 nil 반환" do
    assert_nil AppConfig.extract_spreadsheet_id(nil)
  end

  test "extract_spreadsheet_id: 빈 문자열이면 빈 문자열 반환" do
    assert_equal "", AppConfig.extract_spreadsheet_id("")
  end

  test "extract_spreadsheet_id: URL에서 ID 추출" do
    url = "https://docs.google.com/spreadsheets/d/SPREADSHEET_ID_123/edit"
    assert_equal "SPREADSHEET_ID_123", AppConfig.extract_spreadsheet_id(url)
  end

  test "extract_spreadsheet_id: URL 아닌 값이면 그대로 반환" do
    assert_equal "plain_id", AppConfig.extract_spreadsheet_id("plain_id")
  end

  test "SHEETS_SPREADSHEET_ID 상수 정의됨" do
    assert_equal "google_sheets_spreadsheet_id", AppConfig::SHEETS_SPREADSHEET_ID
  end

  test "SHEETS_ENABLED 상수 정의됨" do
    assert_equal "google_sheets_enabled", AppConfig::SHEETS_ENABLED
  end

  test "key 없으면 invalid" do
    config = AppConfig.new(key: nil, value: "test")
    assert_not config.valid?
  end
end
