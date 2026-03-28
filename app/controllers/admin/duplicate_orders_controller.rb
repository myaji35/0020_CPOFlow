# frozen_string_literal: true

module Admin
  class DuplicateOrdersController < ApplicationController
    before_action :require_manager!

    # GET /admin/duplicate_orders
    def index
      @duplicate_threads = Order.where(parent_order_id: nil)
                                .where.not(gmail_thread_id: nil)
                                .group(:gmail_thread_id)
                                .having("COUNT(*) > 1")
                                .pluck(:gmail_thread_id)

      @groups = @duplicate_threads.map do |thread_id|
        orders = Order.where(gmail_thread_id: thread_id, parent_order_id: nil)
                      .includes(:assignees, :sub_orders, :user)
                      .order(created_at: :asc)
        { thread_id: thread_id, orders: orders }
      end
    end

    # POST /admin/duplicate_orders/merge
    def merge
      main_id = params[:main_order_id].to_i
      merge_ids = Array(params[:merge_order_ids]).map(&:to_i).reject { |id| id == main_id }

      if main_id.zero? || merge_ids.empty?
        redirect_to admin_duplicate_orders_path, alert: "메인 주문과 병합 대상을 선택해 주세요."
        return
      end

      main_order = Order.find(main_id)
      merged_count = 0

      merge_ids.each do |oid|
        order = Order.find_by(id: oid)
        next unless order
        next if order.parent_order_id.present? # 이미 서브 주문

        # 서브 주문의 sub_orders도 메인으로 이관
        order.sub_orders.update_all(parent_order_id: main_order.id)

        # 해당 주문을 메인의 서브 주문으로 변환
        order.update_columns(parent_order_id: main_order.id)

        Activity.create!(
          order: main_order,
          user: current_user,
          action: "order_merged",
          metadata: { merged_order_id: order.id, merged_title: order.title }.to_json
        )
        merged_count += 1
      end

      redirect_to admin_duplicate_orders_path,
                  notice: "#{merged_count}건의 주문을 ##{main_order.id}에 병합했습니다."
    end
  end
end
