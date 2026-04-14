# frozen_string_literal: true

require "test_helper"

class SheetsSyncLogTest < ActiveSupport::TestCase
  def teardown
    SheetsSyncLog.where("spreadsheet_id LIKE ?", "test-%").destroy_all
  end

  test "STATUSES 상수 정의됨" do
    assert_includes SheetsSyncLog::STATUSES, "pending"
    assert_includes SheetsSyncLog::STATUSES, "success"
    assert_includes SheetsSyncLog::STATUSES, "failed"
    assert_includes SheetsSyncLog::STATUSES, "mock"
  end

  test "validates — 잘못된 status 거부" do
    log = SheetsSyncLog.new(status: "unknown", spreadsheet_id: "test-id")
    assert_not log.valid?
  end

  test "create — 유효한 로그 생성" do
    log = SheetsSyncLog.create!(status: "pending", spreadsheet_id: "test-#{SecureRandom.hex(4)}")
    assert log.persisted?
  end

  test "scope recent — 최신 10개 반환" do
    result = SheetsSyncLog.recent
    assert result.is_a?(ActiveRecord::Relation)
    assert result.count <= 10
  end

  test "success? — status 비교" do
    log = SheetsSyncLog.new(status: "success")
    assert log.success?
    assert_not log.failed?
  end

  test "failed? — status 비교" do
    log = SheetsSyncLog.new(status: "failed")
    assert log.failed?
    assert_not log.success?
  end

  test "mock? — status 비교" do
    log = SheetsSyncLog.new(status: "mock")
    assert log.mock?
  end

  test "pending? — status 비교" do
    log = SheetsSyncLog.new(status: "pending")
    assert log.pending?
  end

  test "total_count — 합계 반환" do
    log = SheetsSyncLog.new(
      status: "success",
      orders_count: 10, projects_count: 5, employees_count: 8, visas_count: 3
    )
    assert_equal 26, log.total_count
  end

  test "status_label — 한글 레이블" do
    assert_equal "성공",    SheetsSyncLog.new(status: "success").status_label
    assert_equal "실패",    SheetsSyncLog.new(status: "failed").status_label
    assert_equal "Mock 완료", SheetsSyncLog.new(status: "mock").status_label
    assert_equal "진행중",  SheetsSyncLog.new(status: "pending").status_label
  end
end
