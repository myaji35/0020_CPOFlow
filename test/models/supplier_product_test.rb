# frozen_string_literal: true

require "test_helper"

class SupplierProductTest < ActiveSupport::TestCase
  def setup
    @supplier = Supplier.create!(name: "SP Model Test Supplier #{SecureRandom.hex(4)}", code: "SPMT#{SecureRandom.hex(3)}")
    @product  = Product.create!(name: "SP Model Test Product #{SecureRandom.hex(4)}", code: "PMTS#{SecureRandom.hex(3)}")
  end

  def teardown
    SupplierProduct.where(supplier: @supplier).destroy_all
    @product.destroy if Product.exists?(@product.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "create — 유효한 supplier_product 생성" do
    sp = SupplierProduct.create!(supplier: @supplier, product: @product)
    assert sp.persisted?
  end

  test "belongs_to supplier" do
    sp = SupplierProduct.create!(supplier: @supplier, product: @product)
    assert_equal @supplier, sp.supplier
  end

  test "belongs_to product" do
    sp = SupplierProduct.create!(supplier: @supplier, product: @product)
    assert_equal @product, sp.product
  end
end
