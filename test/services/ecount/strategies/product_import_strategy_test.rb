# frozen_string_literal: true

require "test_helper"

class Ecount::Strategies::ProductImportStrategyTest < ActiveSupport::TestCase
  def setup
    @strategy = Ecount::Strategies::ProductImportStrategy.new
  end

  def teardown
    Product.where("ecount_code LIKE ?", "ECOUNT_PROD%").destroy_all
  end

  test "upsert — 유효한 품목 row 처리" do
    row = {
      ecount_code: "ECOUNT_PROD_#{SecureRandom.hex(4)}",
      name:        "eCount 테스트 품목",
      unit:        "EA",
      category:    "MECH"
    }
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end

  test "upsert — ecount_code 없을 때 name 기반 자동 코드 생성" do
    row = {
      ecount_code: nil,
      code:        nil,
      name:        "자동코드 테스트 품목 #{SecureRandom.hex(4)}",
      unit:        "KG"
    }
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end

  test "upsert — 중복 ecount_code 시 upsert (에러 없음)" do
    code = "ECOUNT_PROD_DUP_#{SecureRandom.hex(3)}"
    row  = { ecount_code: code, name: "중복 품목", unit: "EA" }
    @strategy.upsert(row)
    result = @strategy.upsert(row)
    assert result[:ok], result[:error]
  end
end
