# frozen_string_literal: true

module Admin
  module Ecount
    # eCount 동기화된 품목 목록/상세 (Product 모델 ecount_code 기반)
    class ProductsController < ApplicationController
      before_action :require_manager!

      PER_PAGE = 50

      def index
        @q = params[:q].to_s.strip
        scope = Product.where.not(ecount_code: nil)
        if @q.present?
          like = "%#{@q}%"
          scope = scope.where("name LIKE ? OR ecount_code LIKE ? OR description LIKE ?", like, like, like)
        end

        @total          = scope.count
        @page           = params[:page].to_i.clamp(1, 9_999)
        @page           = 1 if @page <= 0
        @per_page       = PER_PAGE
        @total_pages    = (@total.to_f / @per_page).ceil
        @products       = scope.order(:ecount_code).offset((@page - 1) * @per_page).limit(@per_page)

        @last_sync = EcountSyncLog.where(sync_type: "products", status: :completed).order(:completed_at).last
      end

      def show
        @product = Product.find(params[:id])
      end
    end
  end
end
