class AddUniqueIndexToProductsEcountCode < ActiveRecord::Migration[8.1]
  def up
    if index_exists?(:products, :ecount_code, name: "index_products_on_ecount_code")
      remove_index :products, name: "index_products_on_ecount_code"
    end
    add_index :products, :ecount_code, unique: true, where: "ecount_code IS NOT NULL", name: "index_products_on_ecount_code_unique"
  end

  def down
    remove_index :products, name: "index_products_on_ecount_code_unique"
    add_index :products, :ecount_code, name: "index_products_on_ecount_code"
  end
end
