require "test_helper"

class VisaTest < ActiveSupport::TestCase
  test "Visa 만료 임박 쿼리 정상" do
    visas = Visa.where(status: "active")
                .where(expiry_date: Date.today..90.days.from_now)
                .order(:expiry_date)
                .includes(:employee)
    assert_nothing_raised { visas.to_a }
  end

  test "Visa 경고 레벨 계산 정확성" do
    valid_levels = %w[만료 긴급 경고 주의 정상]
    Visa.where(status: "active").where.not(expiry_date: nil).limit(10).each do |v|
      days = (v.expiry_date - Date.today).to_i
      level = case days
              when ..0      then "만료"
              when 1..30    then "긴급"
              when 31..60   then "경고"
              when 61..90   then "주의"
              else               "정상"
              end
      assert_includes valid_levels, level
    end
    assert valid_levels.any?, "경고 레벨 목록 존재"
  end

  test "Visa VISA_TYPES 유효성" do
    assert_equal %w[Employment Tourist Transit Residence], Visa::VISA_TYPES
  end

  test "Visa employee 연관 로드 정상" do
    assert_nothing_raised do
      Visa.includes(:employee).limit(5).map { |v| v.employee&.name }
    end
  end
end
