# frozen_string_literal: true

class OrderQuote < ApplicationRecord
  belongs_to :order
  belongs_to :supplier

  validates :unit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :currency, inclusion: { in: %w[USD KRW AED EUR] }, allow_nil: true

  scope :by_price, -> { order(unit_price: :asc) }
  scope :selected, -> { where(selected: true) }

  def select!
    order.order_quotes.update_all(selected: false)
    update!(selected: true)
  end

  def formatted_price
    return "-" if unit_price.blank?
    "#{currency || 'USD'} #{number_with_delimiter(unit_price)}"
  end
end
