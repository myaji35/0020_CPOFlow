# frozen_string_literal: true

class Orders::PdfController < ApplicationController
  before_action :set_order

  def quote
    respond_to do |format|
      format.pdf do
        render pdf:      "quote_#{@order.id}_#{Date.today}",
               template: "orders/pdf/quote",
               layout:   "pdf",
               orientation: "Portrait",
               page_size:   "A4"
      end
    end
  end

  def purchase_order
    respond_to do |format|
      format.pdf do
        render pdf:      "po_#{@order.id}_#{Date.today}",
               template: "orders/pdf/purchase_order",
               layout:   "pdf",
               orientation: "Portrait",
               page_size:   "A4"
      end
    end
  end

  private

  def set_order
    @order = Order.find(params[:order_id] || params[:id])
  end
end
