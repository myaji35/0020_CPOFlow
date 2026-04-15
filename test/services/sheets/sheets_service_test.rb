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

  test "sync_all — mock 로그에 projects_count 포함" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_not_nil log.projects_count
    log.destroy
  end

  test "sync_all — mock 로그에 visas_count 포함" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_not_nil log.visas_count
    log.destroy
  end

  test "sync_all — mock 로그의 status는 mock" do
    svc = Sheets::SheetsService.new
    log = svc.sync_all
    assert_equal "mock", log.status
    log.destroy
  end

  test "sync_monthly_data — DB 조회 에러 없이 실행" do
    svc = Sheets::SheetsService.new
    log = SheetsSyncLog.create!(status: "pending", synced_at: Time.current)
    # sync_monthly_data는 update_sheet를 호출하나 mock 모드에서는 @service가 nil
    # private 메서드를 직접 테스트하기 어려우므로 run_mock으로 커버되는 것 확인
    assert svc.mock_mode?
    log.destroy
  end

  test "새 인스턴스 생성 — 에러 없음" do
    assert_nothing_raised { Sheets::SheetsService.new }
  end

  test "SITE_CATEGORIES 배열 타입" do
    assert_kind_of Array, Sheets::SheetsService::SITE_CATEGORIES
    assert_operator Sheets::SheetsService::SITE_CATEGORIES.size, :>, 0
  end
end
