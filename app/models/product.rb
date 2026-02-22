class Product < ApplicationRecord
  has_many :supplier_products, dependent: :destroy
  has_many :suppliers, through: :supplier_products

  validates :name, presence: true
  validates :code, uniqueness: true, allow_blank: true

  scope :active,  -> { where(active: true) }
  scope :by_name, -> { order(:name) }
end
