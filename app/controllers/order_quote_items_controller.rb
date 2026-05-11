# frozen_string_literal: true

class OrderQuoteItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

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
    head :no_content
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
end
