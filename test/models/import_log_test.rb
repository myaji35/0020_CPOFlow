# frozen_string_literal: true

require "test_helper"

class ImportLogTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "import_log_test@example.com") do |u|
      u.name = "Import Log Test"; u.password = "password123"; u.role = :member
    end
    @log = ImportLog.new(user: @user, import_type: :products, filename: "test.csv", status: :pending)
  end

  test "유효한 ImportLog 생성" do
    assert @log.valid?
  end

  test "import_type 없으면 invalid" do
    @log.import_type = nil
    assert_not @log.valid?
  end

  test "filename 없으면 invalid" do
    @log.filename = nil
    assert_not @log.valid?
  end

  test "default status는 pending" do
    log = ImportLog.new(user: @user, import_type: :products, filename: "x.csv")
    assert_equal "pending", log.status
  end

  test "error_rows_array — nil이면 빈 배열" do
    @log.error_details = nil
    assert_equal [], @log.error_rows_array
  end

  test "error_rows_array — JSON 파싱" do
    @log.error_details = '[{"row":2,"error":"invalid"}]'
    result = @log.error_rows_array
    assert_equal 1, result.length
    assert_equal 2, result.first["row"]
  end

  test "preview_rows — nil이면 빈 배열" do
    @log.preview_data = nil
    assert_equal [], @log.preview_rows
  end

  test "progress_percent — total_rows 0이면 0" do
    @log.total_rows = 0
    assert_equal 0, @log.progress_percent
  end

  test "progress_percent — 계산 정상" do
    @log.total_rows = 100
    @log.success_rows = 80
    @log.error_rows = 5
    assert_equal 85, @log.progress_percent
  end

  test "import_type_label — products → 품목" do
    @log.import_type = :products
    assert_equal "품목", @log.import_type_label
  end

  test "import_type_label — suppliers → 거래처" do
    @log.import_type = :suppliers
    assert_equal "거래처", @log.import_type_label
  end

  test "import_type_label — orders → 거래이력" do
    @log.import_type = :orders
    assert_equal "거래이력", @log.import_type_label
  end

  test "status_label — pending → 대기 중" do
    @log.status = :pending
    assert_equal "대기 중", @log.status_label
  end

  test "status_label — completed → 완료" do
    @log.status = :completed
    assert_equal "완료", @log.status_label
  end

  test "status_label — failed → 실패" do
    @log.status = :failed
    assert_equal "실패", @log.status_label
  end
end
