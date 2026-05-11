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
    head :no_content
  end

  def update
    head :no_content
  end

  def destroy
    head :no_content
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
