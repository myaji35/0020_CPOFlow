class Supplier < ApplicationRecord
  has_many :contact_persons,   as: :contactable, dependent: :destroy
  has_many :supplier_products, dependent: :destroy
  has_many :products,          through: :supplier_products
  has_many :orders,            dependent: :nullify

  CREDIT_GRADES = %w[A B C D].freeze
  PAYMENT_TERMS = %w[NET30 NET60 NET90 COD Advance].freeze

  validates :name, presence: true

  scope :active,  -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  def primary_contact    = contact_persons.find_by(primary: true) || contact_persons.first
  def total_supply_value = orders.sum(:estimated_value).to_f
  def industry_label
    { "nuclear" => "원전", "hydro" => "수력", "tunnel" => "터널",
      "gtx" => "GTX", "construction" => "건설", "general" => "일반" }[industry] || industry
  end
end
