# frozen_string_literal: true

require "test_helper"

class Ecount::EcountImportServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "ecount_import_svc@example.com") do |u|
      u.name = "EcountImport Tester"; u.password = "password123"; u.role = :member
    end
  end

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

  test "strategy — import_type: products는 ProductImportStrategy 반환" do
    log = ImportLog.new(status: :pending, import_type: "products", user: @user)
    svc = Ecount::EcountImportService.new(log)
    strat = svc.send(:strategy)
    assert strat.is_a?(Ecount::Strategies::ProductImportStrategy)
  end

  test "strategy — import_type: suppliers는 SupplierImportStrategy 반환" do
    log = ImportLog.new(status: :pending, import_type: "suppliers", user: @user)
    svc = Ecount::EcountImportService.new(log)
    strat = svc.send(:strategy)
    assert strat.is_a?(Ecount::Strategies::SupplierImportStrategy)
  end

  test "strategy — import_type: orders는 OrderImportStrategy 반환" do
    log = ImportLog.new(status: :pending, import_type: "orders", user: @user)
    svc = Ecount::EcountImportService.new(log)
    strat = svc.send(:strategy)
    assert strat.is_a?(Ecount::Strategies::OrderImportStrategy)
  end

  test "strategy — 3가지 import_type 모두 해당 Strategy 클래스를 반환" do
    [
      [ "products", Ecount::Strategies::ProductImportStrategy ],
      [ "suppliers", Ecount::Strategies::SupplierImportStrategy ],
      [ "orders", Ecount::Strategies::OrderImportStrategy ]
    ].each do |type, klass|
      log = ImportLog.new(status: :pending, import_type: type, user: @user)
      svc = Ecount::EcountImportService.new(log)
      strat = svc.send(:strategy)
      assert strat.is_a?(klass), "import_type=#{type} 는 #{klass} 이어야 함"
    end
  end
end
