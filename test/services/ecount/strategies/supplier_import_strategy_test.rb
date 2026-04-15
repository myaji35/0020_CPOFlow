# frozen_string_literal: true

require "test_helper"

class Ecount::Strategies::SupplierImportStrategyTest < ActiveSupport::TestCase
  def setup
    @strategy = Ecount::Strategies::SupplierImportStrategy.new
  end

  def teardown
    Supplier.where("ecount_code LIKE ?", "ECOUNT_SUPP%").destroy_all
  end

  test "upsert — 유효한 공급사 row 처리" do
    row = {
      ecount_code: "ECOUNT_SUPP_#{SecureRandom.hex(4)}",
      name:        "eCount 테스트 공급사",
      country:     "KR"
    }
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end

  test "upsert — 중복 ecount_code 시 upsert (에러 없음)" do
    code = "ECOUNT_SUPP_DUP_#{SecureRandom.hex(3)}"
    row  = { ecount_code: code, name: "중복 공급사" }
    @strategy.upsert(row)
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end
end
