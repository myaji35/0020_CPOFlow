# frozen_string_literal: true

class OrderQuotesController < ApplicationController
  before_action :set_order, only: %i[new create]
  before_action :set_quote, only: %i[destroy select]

  def new
    @quote = @order.order_quotes.build
    @suppliers = Supplier.order(:name)
  end

  def create
    @quote = @order.order_quotes.build(quote_params)
    if @quote.save
      redirect_to @order, notice: "견적이 등록되었습니다."
    else
      @suppliers = Supplier.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    order = @quote.order
    @quote.destroy
    redirect_to order, notice: "견적을 삭제했습니다."
  end

  def select
    @quote.select!
    @quote.order.update(supplier_id: @quote.supplier_id)
    redirect_to @quote.order, notice: "#{@quote.supplier.name} 견적이 선택되었습니다."
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end

  def set_quote
    @quote = OrderQuote.find(params[:id])
  end

  def quote_params
    params.require(:order_quote).permit(
      :supplier_id, :unit_price, :currency, :lead_time_days,
      :validity_date, :notes
    )
  end
end
