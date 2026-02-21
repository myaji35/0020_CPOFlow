class SupplierProduct < ApplicationRecord
  belongs_to :supplier
  belongs_to :product

  validates :supplier, :product, presence: true

  def display_price
    return "미정" unless price
    "#{currency} #{format("%.2f", price)}"
  end
end
