# frozen_string_literal: true

require "test_helper"

class Ecount::Strategies::OrderImportStrategyTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "order_import_strat_test@example.com") do |u|
      u.name = "Order Import Strat Test"; u.password = "password123"; u.role = :member
    end
    @strategy = Ecount::Strategies::OrderImportStrategy.new(@user)
  end

  def teardown
    Order.where("source_email_id LIKE ?", "ecount_%").where(user: @user).destroy_all
  end

  test "STATUS_MAP 상수 정의됨" do
    map = Ecount::Strategies::OrderImportStrategy::STATUS_MAP
    assert_equal "new_rfq",        map["견적요청"]
    assert_equal "get_grn",        map["납품완료"]
    assert_equal "make_quo",       map["검토중"]
  end

  test "upsert — 유효한 row 처리 성공" do
    row = {
      source_ref:     "ECOUNT_TEST_#{SecureRandom.hex(4)}",
      ecount_status:  "견적요청",
      customer_name:  "테스트 고객",
      item_name:      "테스트 품목",
      due_date:       "2026-12-31"
    }
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end

  test "upsert — 중복 row는 upsert (에러 없음)" do
    ref = "ECOUNT_DUP_#{SecureRandom.hex(4)}"
    row = { source_ref: ref, ecount_status: "납품완료", customer_name: "고객" }
    @strategy.upsert(row)
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end
end
