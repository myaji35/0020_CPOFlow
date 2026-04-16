# frozen_string_literal: true

module Admin
  module Ecount
    # eCount 연동 거래처 (Client + Supplier 통합 뷰, ecount_code 기반)
    class CustomersController < ApplicationController
      before_action :require_manager!

      PER_PAGE = 50

      def index
        @q = params[:q].to_s.strip
        @type_filter = params[:type].presence # "client", "supplier", nil(전체)

        clients   = Client.where.not(ecount_code: [ nil, "" ]).select("id, name, code, ecount_code, ecount_synced_at, country, contact_email, contact_phone, 'Client' AS record_type")
        suppliers = Supplier.where.not(ecount_code: [ nil, "" ]).select("id, name, code, ecount_code, ecount_synced_at, country, contact_email, contact_phone, 'Supplier' AS record_type")

        case @type_filter
        when "client"
          combined = clients
        when "supplier"
          combined = suppliers
        else
          combined = Client.from("(#{clients.to_sql} UNION ALL #{suppliers.to_sql}) AS clients")
        end

        if @q.present?
          like = "%#{@q}%"
          combined = combined.where("name LIKE ? OR ecount_code LIKE ? OR code LIKE ?", like, like, like)
        end

        @total       = combined.count
        @page        = params[:page].to_i.clamp(1, 9_999)
        @per_page    = PER_PAGE
        @total_pages = (@total.to_f / @per_page).ceil
        @customers   = combined.order(:name).offset((@page - 1) * @per_page).limit(@per_page)

        @last_sync = EcountSyncLog.where(sync_type: "customers").order(:completed_at).last
      end

      def show
        @type = params[:type] # "client" or "supplier"
        @customer = if @type == "supplier"
          Supplier.find(params[:id])
        else
          Client.find(params[:id])
        end
        @orders = Order.where(
          @type == "supplier" ? { supplier_id: @customer.id } : { client_id: @customer.id }
        ).order(created_at: :desc).limit(30).includes(:card_status)
      end
    end
  end
end
