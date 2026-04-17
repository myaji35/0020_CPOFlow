# frozen_string_literal: true

module Admin
  # eCountERP API 동기화 이력 조회 + 수동 즉시 동기화 트리거
  class EcountSyncController < ApplicationController
    before_action :require_manager!

    # GET /admin/ecount_sync
    def index
      @logs = EcountSyncLog.recent.limit(5)
      @products_last  = EcountSyncLog.where(sync_type: "products",  status: :completed).order(:completed_at).last
      @customers_last = EcountSyncLog.where(sync_type: "customers", status: :completed).order(:completed_at).last
      @failed_today   = EcountSyncLog.failed_today.count

      # 실제 현황
      @total_products_db     = Product.count
      @products_with_ecount  = Product.where.not(ecount_code: nil).count

      # ISS-220: eCount ↔ CPOFlow 값 불일치(conflict) 현황
      # 스냅샷이 있는 레코드 중 diff가 1개 이상인 것만 카운트
      @supplier_conflicts = Supplier.where.not(ecount_snapshot: nil)
                                    .select { |s| s.ecount_diff.any? }
      @client_conflicts   = Client.where.not(ecount_snapshot: nil)
                                  .select { |c| c.ecount_diff.any? }
      @conflict_total     = @supplier_conflicts.size + @client_conflicts.size

      # 연결 상태 + 일일 규정 (캐시에 있는 세션 정보만 — 새 호출 없음)
      @session_cached    = Rails.cache.read(:ecount_session_id).present?
      @daily_quota_info  = Rails.cache.read(:ecount_daily_quota)  # 최근 호출의 QUANTITY_INFO
      @connection_ready  = Rails.application.credentials.dig(:ecount).present? ||
                           ENV["ECOUNT_API_CERT_KEY"].present?

      # 거래내역 이관 검토 상태
      @transaction_sync_status = {
        # 아직 OAPI 엔드포인트 미확보 — Phase 계획만 노출
        sales_slips:     { state: "planned", total: nil, note: "/Sales/GetListSales (엔드포인트 확인 중)" },
        purchase_slips:  { state: "planned", total: nil, note: "/Purchase/GetListPurchase (엔드포인트 확인 중)" },
        inventory_stock: { state: "planned", total: Product.count, note: "/InventoryStatus/GetListInventory (엔드포인트 확인 중)" }
      }
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
