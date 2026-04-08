class OrderFlowsController < ApplicationController
  before_action :authenticate_user!

  def show
    @order = Order.find(params[:order_id])
    @graph = OrderGraphBuilder.new(@order, depth: 3, include_suggested: true).call
    @suggestions = OrderLink.suggested.where(
      "(source_type = ? AND source_id = ?) OR (target_type = ? AND target_id = ?)",
      @order.class.name, @order.id, @order.class.name, @order.id
    )
    render layout: false
  end
end
