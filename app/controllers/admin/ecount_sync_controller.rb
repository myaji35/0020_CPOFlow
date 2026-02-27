# frozen_string_literal: true

module Admin
  # eCountERP API 동기화 이력 조회 + 수동 즉시 동기화 트리거
  class EcountSyncController < ApplicationController
    before_action :require_manager!

    # GET /admin/ecount_sync
    def index
      @logs = EcountSyncLog.recent.limit(50)
      @products_last  = EcountSyncLog.where(sync_type: "products",  status: :completed).order(:completed_at).last
      @customers_last = EcountSyncLog.where(sync_type: "customers", status: :completed).order(:completed_at).last
      @failed_today   = EcountSyncLog.failed_today.count
    end

    # POST /admin/ecount_sync/trigger
    def trigger
      type = params[:sync_type].presence_in(%w[products customers])
      unless type
        return redirect_to admin_ecount_sync_index_path, alert: "잘못된 동기화 유형입니다."
      end

      job = type == "products" ? EcountProductSyncJob : EcountCustomerSyncJob
      job.perform_later
      redirect_to admin_ecount_sync_index_path,
                  notice: "#{type == 'products' ? '품목' : '거래처'} 동기화를 백그라운드에서 시작했습니다."
    end
  end
end
