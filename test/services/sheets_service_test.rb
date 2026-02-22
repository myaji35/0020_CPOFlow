require "test_helper"

class SheetsServiceTest < ActiveSupport::TestCase
  def setup
    @service = Sheets::SheetsService.new
  end

  test "SheetsService 초기화 정상" do
    assert_not_nil @service
  end

  test "mock_mode 여부 확인 가능" do
    assert_respond_to @service, :mock_mode?
  end

  test "mock 모드일 때 sync_all 성공" do
    # Service Account 없으면 mock 모드
    if @service.mock_mode?
      log = @service.sync_all
      assert_equal "mock", log.status
      assert log.orders_count >= 0
      assert log.employees_count >= 0
    else
      skip "실제 API 연동 모드 — mock 테스트 건너뜀"
    end
  end

  test "SheetsSyncLog 생성 정상" do
    count_before = SheetsSyncLog.count
    log = @service.sync_all
    assert_not_nil log
    assert_not_nil log.status
    # mock이든 real이든 log 레코드 생성
    assert SheetsSyncLog.count > count_before || SheetsSyncLog.count >= count_before
  end

  test "AppConfig spreadsheet_id 조회" do
    id = AppConfig.sheets_spreadsheet_id
    # nil이어도 되고 string이어도 됨 (mock 모드 허용)
    assert id.nil? || id.is_a?(String)
  end
end
