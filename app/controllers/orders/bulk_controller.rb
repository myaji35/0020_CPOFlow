# frozen_string_literal: true

class Orders::BulkController < ApplicationController
  before_action :require_manager_or_admin!

  def update
    orders = Order.where(id: params[:order_ids])
    return redirect_back(fallback_location: orders_path, alert: "선택된 주문이 없습니다.") if orders.empty?

    case params[:action_type]
    when "status"
      orders.update_all(status: Order.statuses[params[:status]])
      notice = "#{orders.count}건 상태를 '#{Order::STATUS_LABELS[params[:status]]}'로 변경했습니다."
    when "priority"
      orders.update_all(priority: Order.priorities[params[:priority]])
      notice = "#{orders.count}건 우선순위를 변경했습니다."
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
    orders = Order.where(id: params[:order_ids])
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
          o.priority,
          o.due_date&.strftime("%Y-%m-%d"),
          o.estimated_value,
          o.assignees.map(&:name).join(", "),
          o.created_at.strftime("%Y-%m-%d")
        ]
      end
    end
  end
end
