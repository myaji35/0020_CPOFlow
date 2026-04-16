# frozen_string_literal: true

module Admin
  module Ecount
    # eCount 동기화된 거래내역 (Order 모델 ecount 메타 기반)
    # 현재 판매/구매 전표 OAPI 미연동 — Phase 2 계획만 노출
    class TransactionsController < ApplicationController
      before_action :require_manager!

      PER_PAGE = 50

      def index
        @q = params[:q].to_s.strip
        # Order에 ecount_slip_no 같은 컬럼이 아직 없음 → reference_no 기반 임시 표시
        # Phase 2 구현 후 실제 ecount 거래내역만 필터링
        scope = Order.not_archived.where.not(reference_no: [ nil, "" ])
        if @q.present?
          like = "%#{@q}%"
          scope = scope.where("reference_no LIKE ? OR original_email_subject LIKE ?", like, like)
        end

        @total       = scope.count
        @page        = params[:page].to_i.clamp(1, 9_999)
        @page        = 1 if @page <= 0
        @per_page    = PER_PAGE
        @total_pages = (@total.to_f / @per_page).ceil
        @transactions = scope.order(created_at: :desc).offset((@page - 1) * @per_page).limit(@per_page)
                              .includes(:client, :supplier, :card_status)

        @sync_pending_reason = "판매/구매 전표 OAPI 엔드포인트 미확보 — Phase 2 계획 (Settings → eCount API 동기화 참조)"
      end
    end
  end
end
