class AssignmentsController < ApplicationController
  # ISS-261: viewer read-only — 담당자 배정/해제는 member 이상만
  before_action :require_member!
  before_action :set_order

  def create
    @assignment = @order.assignments.find_or_initialize_by(employee_id: params[:employee_id])
    if @assignment.new_record? && @assignment.save
      Activity.create!(order: @order, user: current_user, action: "assignee_added")
    end
    respond_after_change
  end

  def destroy
    assignment = @order.assignments.find(params[:id])
    assignment.destroy
    Activity.create!(order: @order, user: current_user, action: "assignee_removed")
    respond_after_change
  end

  private

  # 2026-04-29: 드로어 안에서 담당자 변경 시 redirect 로 인한 드로어 닫힘 / 카드 숨김 차단.
  # JSON 요청(드로어 fetch 후속 액션) → 200 OK + 새 담당자 목록 partial.
  # HTML 요청 → redirect_back (기존 동작 유지).
  def respond_after_change
    respond_to do |format|
      format.json {
        render json: {
          status: "ok",
          assignees: @order.assignees.map { |e| { id: e.id, name: e.display_name } }
        }
      }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "order-assignees-#{@order.id}",
          partial: "orders/drawer_assignees",
          locals: { order: @order.reload }
        )
      }
      format.html { redirect_back fallback_location: order_path(@order) }
    end
  end

  def set_order
    # ISS-257: Branch 격리
    @order = scoped_orders.find(params[:order_id])
  end
end
