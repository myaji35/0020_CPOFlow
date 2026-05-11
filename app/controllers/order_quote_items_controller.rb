# frozen_string_literal: true

class OrderQuoteItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

  ALLOWED_FIELDS = %w[item description model_part_no manufacturer_brand unit qty remarks].freeze

  def index
    @items = @order.quote_items.ordered
    @sources = AttachmentQuoteAnalysis.where(order_id: @order.id, status: "completed")
                                       .includes(:active_storage_attachment)
    render partial: "orders/quote_items_frame",
           locals: { order: @order, items: @items, sources: @sources }
  end

  def create
    is_first = @order.quote_items.empty?
    next_row = (@order.quote_items.maximum(:row_no) || 0) + 1
    item = @order.quote_items.create!(row_no: next_row, item: "")

    if is_first
      sources = AttachmentQuoteAnalysis.where(order_id: @order.id, status: "completed")
                                         .includes(:active_storage_attachment)
      render turbo_stream: turbo_stream.replace(
        "quote-items-frame-#{@order.id}",
        partial: "orders/quote_items_frame",
        locals: { order: @order, items: @order.quote_items.ordered, sources: sources }
      )
    else
      render turbo_stream: turbo_stream.append(
        "quote-items-tbody-#{@order.id}",
        partial: "orders/quote_item_row",
        locals: { item: item }
      )
    end
  end

  def update
    item = @order.quote_items.find(params[:id])
    field = params[:field].to_s
    return head :unprocessable_entity unless ALLOWED_FIELDS.include?(field)

    item.update!(
      field => normalize(field, params[:value]),
      user_edited: true,
      edited_by_user_id: current_user.id
    )
    render turbo_stream: turbo_stream.replace(
      "quote-item-#{item.id}",
      partial: "orders/quote_item_row",
      locals: { item: item }
    )
  end

  def destroy
    item = @order.quote_items.find(params[:id])
    item.destroy
    render turbo_stream: turbo_stream.remove("quote-item-#{item.id}")
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end

  def normalize(field, raw)
    return BigDecimal(raw.to_s.scan(/[\d.]+/).first || "0") if field == "qty" && raw.present?
    raw
  rescue ArgumentError
    nil
  end
end
