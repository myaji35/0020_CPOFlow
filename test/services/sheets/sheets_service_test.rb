# frozen_string_literal: true

require "test_helper"

class Sheets::SheetsServiceTest < ActiveSupport::TestCase
  test "SCOPE 상수 정의됨" do
    assert_equal "https://www.googleapis.com/auth/spreadsheets", Sheets::SheetsService::SCOPE
  end

  test "SITE_CATEGORIES 상수 정의됨" do
    cats = Sheets::SheetsService::SITE_CATEGORIES
    assert_includes cats, "nuclear"
    assert_includes cats, "hydro"
    assert_includes cats, "tunnel"
    assert_includes cats, "gtx"
  end

  test "credentials/spreadsheet_id 미설정 시 mock_mode 활성화" do
    svc = Sheets::SheetsService.new
    assert svc.mock_mode?
  end

  test "sync_all — mock 모드에서 SheetsSyncLog 생성" do
    svc = Sheets::SheetsService.new
    assert svc.mock_mode?
    log = svc.sync_all
    assert log.is_a?(SheetsSyncLog)
    assert_equal "mock", log.status
    log.destroy
  end

  test "sync_all — mock 로그에 orders_count 포함" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_not_nil log.orders_count
    log.destroy
  end

  test "sync_all — mock 로그에 employees_count 포함" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_not_nil log.employees_count
    log.destroy
  end

  test "sync_all — mock 로그에 synced_at 포함" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_not_nil log.synced_at
    log.destroy
  end
end
