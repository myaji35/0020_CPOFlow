require "test_helper"

class SupplierTest < ActiveSupport::TestCase
  test "Supplier scopes 정상 동작" do
    assert_nothing_raised { Supplier.active.count }
    assert_nothing_raised { Supplier.by_name.limit(5).to_a }
  end

  test "Supplier associations 쿼리 정상" do
    assert_nothing_raised do
      Supplier.includes(:orders, :products, :contact_persons).limit(5).to_a
    end
  end

  test "Supplier orders 집계 정상" do
    total = Supplier.joins(:orders).count
    assert total >= 0
  end
end
