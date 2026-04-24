# frozen_string_literal: true

class Orders::BulkController < ApplicationController
  before_action :require_manager_or_admin!

  def update
    # ISS-257: Branch 격리 — manager가 타 branch 오더를 일괄 업데이트하지 못하게 차단
    orders = scoped_orders.where(id: params[:order_ids])
    return redirect_back(fallback_location: orders_path, alert: "선택된 주문이 없습니다.") if orders.empty?

    case params[:action_type]
    when "status"
      orders.update_all(status: Order.statuses[params[:status]])
      notice = "#{orders.count}건 상태를 '#{Order::STATUS_LABELS[params[:status]]}'로 변경했습니다."
    when "priority", "card_status"
      cs_key = params[:card_status].presence || params[:priority]
      cs = CardStatus.find_by(key: cs_key)
      if cs
        orders.update_all(card_status_id: cs.id, card_status_manually_set_at: Time.current)
        notice = "#{orders.count}건 상태를 '#{cs.name}'로 변경했습니다."
      end
    when "assign"
      user = User.find_by(id: params[:user_id])
      if user
        orders.each do |order|
          Assignment.find_or_create_by!(order: order, user: user)
        end
        notice = "#{orders.count}건에 #{user.display_name}을 배정했습니다."
      end
    end

    redirect_back fallback_location: orders_path, notice: notice || "처리 완료"
  end

  def export_csv
    # ISS-257: Branch 격리
    orders = scoped_orders.where(id: params[:order_ids])
                          .includes(:client, :supplier, :project, :assignees)
    csv_data = generate_csv(orders)
    send_data csv_data,
              filename: "orders_#{Date.today}.csv",
              type: "text/csv; charset=UTF-8"
  end

  private

  def require_manager_or_admin!
    unless current_user&.admin? || current_user&.manager?
      redirect_to orders_path, alert: "권한이 없습니다."
    end
  end

  def generate_csv(orders)
    require "csv"
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << %w[ID 주문명 발주처 거래처 현장 상태 우선순위 마감일 예상금액 담당자 생성일]
      orders.each do |o|
        csv << [
          o.id, o.title,
          o.client&.name || o.customer_name,
          o.supplier&.name,
          o.project&.name,
          Order::STATUS_LABELS[o.status],
          o.card_status&.key,
          o.due_date&.strftime("%Y-%m-%d"),
          o.estimated_value,
          o.assignees.map(&:name).join(", "),
          o.created_at.strftime("%Y-%m-%d")
        ]
      end
    end
  end
end
