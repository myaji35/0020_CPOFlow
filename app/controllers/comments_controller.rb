class CommentsController < ApplicationController
  before_action :set_order

  def create
    @comment = @order.comments.build(body: params[:body], user: current_user)
    @comment.save
    redirect_to @order
  end

  def destroy
    @order.comments.find(params[:id]).destroy
    redirect_to @order
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
