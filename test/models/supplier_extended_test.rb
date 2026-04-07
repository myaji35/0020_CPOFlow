require "test_helper"

class SupplierExtendedTest < ActiveSupport::TestCase
  test "Supplier: name 없으면 invalid" do
    supplier = Supplier.new
    assert_not supplier.valid?
    assert supplier.errors[:name].any?
  end

  test "Supplier: name 있으면 valid" do
    supplier = Supplier.new(name: "Test Supplier")
    assert supplier.valid?
  end

  test "industry_label: nuclear이면 원전" do
    supplier = Supplier.new(name: "Test", industry: "nuclear")
    assert_equal "원전", supplier.industry_label
  end

  test "industry_label: nil이면 nil" do
    supplier = Supplier.new(name: "Test", industry: nil)
    assert_nil supplier.industry_label
  end

  test "total_supply_value: 예외 없음" do
    assert_nothing_raised do
      Supplier.active.limit(3).each { |s| s.total_supply_value }
    end
  end

  test "CREDIT_GRADES 상수 확인" do
    assert_includes Supplier::CREDIT_GRADES, "A"
  end

  test "PAYMENT_TERMS 상수 확인" do
    assert_includes Supplier::PAYMENT_TERMS, "NET30"
    assert_includes Supplier::PAYMENT_TERMS, "COD"
  end

  test "active scope 동작" do
    assert_nothing_raised { Supplier.active.count }
  end

  test "by_name scope 동작" do
    assert_nothing_raised { Supplier.by_name.limit(5).to_a }
  end

  test "associations 쿼리 정상" do
    assert_nothing_raised do
      Supplier.includes(:contact_persons, :supplier_products).limit(5).to_a
    end
  end
end
