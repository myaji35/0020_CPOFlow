# frozen_string_literal: true

module Admin
  module Ecount
    # eCount 거래내역 — Order 모델 기반 실질 거래 현황
    class TransactionsController < ApplicationController
      before_action :require_manager!

      PER_PAGE = 50

      # 정렬 허용 컬럼
      SORTABLE = %w[reference_no created_at estimated_value status].freeze

      def index
        @q = params[:q].to_s.strip

        scope = Order.not_archived.where.not(reference_no: [nil, ""])

        # 텍스트 검색
        if @q.present?
          like = "%#{@q}%"
          scope = scope.where("reference_no LIKE ? OR original_email_subject LIKE ?", like, like)
        end

        # 상태 필터
        if params[:status].present? && Order.statuses.key?(params[:status])
          scope = scope.where(status: params[:status])
        end

        # 발주처 필터
        if params[:client_id].present?
          scope = scope.where(client_id: params[:client_id])
        end

        # 거래처 필터
        if params[:supplier_id].present?
          scope = scope.where(supplier_id: params[:supplier_id])
        end

        # 기간 필터
        case params[:period]
        when "month"
          scope = scope.where(created_at: Time.current.beginning_of_month..)
        when "3months"
          scope = scope.where(created_at: 3.months.ago.beginning_of_day..)
        end
        # "all" 또는 빈값 → 필터 없음

        # 집계 (필터 적용 후)
        @total        = scope.count
        @total_amount = scope.sum(:estimated_value).to_f
        @status_dist  = scope.group(:status).count

        # 진행 중 = new_rfq ~ get_grn (0~6), 완료 = give_up(7) + done(8)
        in_progress_statuses = %w[new_rfq make_quo pending_po new_po delivery_items problem get_grn]
        completed_statuses   = %w[give_up done]
        @in_progress = @status_dist.select { |k, _| in_progress_statuses.include?(k) }.values.sum
        @completed   = @status_dist.select { |k, _| completed_statuses.include?(k) }.values.sum

        # 정렬
        sort_col = SORTABLE.include?(params[:sort]) ? params[:sort] : "created_at"
        sort_dir = params[:dir] == "asc" ? :asc : :desc
        @sort_col = sort_col
        @sort_dir = sort_dir

        # 페이지네이션
        @page        = [params[:page].to_i, 1].max
        @per_page    = PER_PAGE
        @total_pages = [(@total.to_f / @per_page).ceil, 1].max

        @transactions = scope.order(sort_col => sort_dir)
                             .offset((@page - 1) * @per_page).limit(@per_page)
                             .includes(:client, :supplier, :card_status)

        # 필터 드롭다운 옵션
        @clients   = Client.where(id: Order.not_archived.where.not(client_id: nil).select(:client_id)).order(:name)
        @suppliers = Supplier.where(id: Order.not_archived.where.not(supplier_id: nil).select(:supplier_id)).order(:name)
      end

      private

      def filter_params
        params.permit(:q, :status, :client_id, :supplier_id, :period, :sort, :dir, :page)
      end
      helper_method :filter_params
    end
  end
end
