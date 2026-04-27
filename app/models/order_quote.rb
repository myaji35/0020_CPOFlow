# frozen_string_literal: true

class OrderQuote < ApplicationRecord
  include GraphNode

  belongs_to :order
  belongs_to :supplier

  validates :unit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :currency, inclusion: { in: %w[AED USD KRW EUR] }, allow_nil: true

  after_create_commit :create_quoted_link

  scope :by_price, -> { order(unit_price: :asc) }
  scope :selected, -> { where(selected: true) }

  def select!
    order.order_quotes.update_all(selected: false)
    update!(selected: true)
  end

  def formatted_price
    return "-" if unit_price.blank?
    "#{currency || 'AED'} #{number_with_delimiter(unit_price)}"
  end

  private

  def create_quoted_link
    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   order_id,
      target_type: "OrderQuote",
      target_id:   id,
      relation:    "quoted_as"
    ) do |link|
      link.status     = OrderLink::STATUSES.first   # "confirmed" — 매직 문자열 회피
      link.confidence = 1.0
      link.metadata   = { "source" => "system_event", "trigger" => "OrderQuote.after_create" }
    end
  end
end
