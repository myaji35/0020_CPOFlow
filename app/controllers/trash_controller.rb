class TrashController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order, only: %i[restore destroy]

  def index
    base = Order.archived.order(archived_at: :desc)
    @orders = current_user.admin? ? base : base.joins(:user).where(users: { branch: current_user.branch })
  end

  def restore
    @order.restore!
    respond_to do |format|
      format.html { redirect_to trash_path, notice: "복원했습니다 — 칸반에서 확인하세요." }
      format.json { render json: { success: true, restored: true } }
    end
  end

  def destroy
    @order.destroy_permanently!
    respond_to do |format|
      format.html { redirect_to trash_path, notice: "영구 삭제했습니다." }
      format.json { render json: { success: true, permanent: true } }
    end
  end

  def empty
    return head :forbidden unless current_user.admin?
    count = Order.archived.count
    Order.archived.destroy_all
    redirect_to trash_path, notice: "휴지통 비움 — #{count}건 영구 삭제."
  end

  private

  def set_order
    base = Order.archived
    base = base.joins(:user).where(users: { branch: current_user.branch }) unless current_user.admin?
    @order = base.find(params[:id])
  end
end
