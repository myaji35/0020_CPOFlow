# frozen_string_literal: true

module Admin
  class DuplicateOrdersController < ApplicationController
    before_action :require_manager!

    # GET /admin/duplicate_orders
    def index
      # ISS-258: Branch 격리 — 현재 사용자 branch의 중복만 노출 (admin은 전체)
      base = scoped_orders.where(parent_order_id: nil).where.not(gmail_thread_id: nil)

      @duplicate_threads = base.group(:gmail_thread_id)
                               .having("COUNT(*) > 1")
                               .pluck(:gmail_thread_id)

      @groups = @duplicate_threads.map do |thread_id|
        orders = base.where(gmail_thread_id: thread_id)
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

      # ISS-258: Branch 격리 — main/merge 모두 scoped_orders 범위 내에서만 허용
      main_order = scoped_orders.find_by(id: main_id)
      unless main_order
        redirect_to admin_duplicate_orders_path, alert: "메인 주문을 찾을 수 없거나 접근 권한이 없습니다."
        return
      end

      main_branch = main_order.user&.branch
      merged_count = 0
      blocked_count = 0

      merge_ids.each do |oid|
        order = scoped_orders.find_by(id: oid)
        unless order
          blocked_count += 1
          next
        end
        next if order.parent_order_id.present? # 이미 서브 주문

        # ISS-258: 서로 다른 branch 오더 병합 차단 (admin이라도 데이터 오염 방지)
        if main_branch.present? && order.user&.branch.present? && order.user.branch != main_branch
          blocked_count += 1
          next
        end

        # 서브 주문의 sub_orders도 메인으로 이관
        order.sub_orders.update_all(parent_order_id: main_order.id)

        # 해당 주문을 메인의 서브 주문으로 변환
        order.update_columns(parent_order_id: main_order.id)

        Activity.create!(
          order: main_order,
          user: current_user,
          action: "order_merged"
        )
        merged_count += 1
      end

      msg = "#{merged_count}건의 주문을 ##{main_order.id}에 병합했습니다."
      msg += " (다른 branch/권한으로 #{blocked_count}건 차단)" if blocked_count.positive?
      redirect_to admin_duplicate_orders_path, notice: msg
    end
  end
end
