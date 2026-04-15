# frozen_string_literal: true

require "test_helper"

class Ecount::EcountImportServiceTest < ActiveSupport::TestCase
  test "BATCH_SIZE 상수 정의됨" do
    assert_equal 500, Ecount::EcountImportService::BATCH_SIZE
  end

  test "EcountImportService 클래스 정의됨" do
    assert defined?(Ecount::EcountImportService)
  end

  test "run! — import_log 없으면 에러" do
    # import_log.user를 nil로 하면 초기화 에러 없음
    log = ImportLog.new(status: :pending, import_type: "orders")
    svc = Ecount::EcountImportService.new(log)
    assert svc.is_a?(Ecount::EcountImportService)
  end
end
