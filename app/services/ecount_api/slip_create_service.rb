# frozen_string_literal: true

module EcountApi
  # CPOFlow Order → eCountERP 매출 전표 자동 생성
  # Order confirmed 상태 전환 시 EcountSlipCreateJob에서 호출
  # 중복 방지: ecount_slip_no 이미 존재하면 스킵
  class SlipCreateService < BaseService
    def initialize(order)
      @order = order
    end

    def create!
      # 이미 전표 있으면 스킵 (멱등성 보장)
      if @order.ecount_slip_no.present?
        Rails.logger.info "[EcountApi::Slip] Order##{@order.id} 이미 전표 있음 (#{@order.ecount_slip_no}) — 스킵"
        return { ok: true, skipped: true, slip_no: @order.ecount_slip_no }
      end

      session  = AuthService.session_id
      payload  = build_payload(session)
      response = post("/Sale/SalesOrder/SaveSalesOrder", payload)

      slip_no = Array(response).dig(0, "SLIP_NO")
      raise EcountApi::ApiError, "전표 번호(SLIP_NO) 응답 없음" unless slip_no.present?

      @order.update_columns(
        ecount_slip_no:   slip_no,
        ecount_synced_at: Time.current
      )

      Rails.logger.info "[EcountApi::Slip] 전표 생성 성공: Order##{@order.id} → #{slip_no}"
      { ok: true, slip_no: slip_no }

    rescue EcountApi::AuthError => e
      handle_failure(e)
    rescue EcountApi::ApiError => e
      handle_failure(e)
    rescue StandardError => e
      handle_failure(e)
    end

    private

    def build_payload(session)
      {
        "SESSION_ID" => session,
        "SLIP_DATA"  => [ {
          "CUST_CD"   => resolve_customer_code,
          "PROD_CD"   => resolve_product_code,
          "QTY"       => (@order.respond_to?(:quantity) ? @order.quantity : 1) || 1,
          "PRICE"     => @order.estimated_value.to_f,
          "CURR_CD"   => @order.respond_to?(:currency) ? (@order.currency.presence || "USD") : "USD",
          "REMARK"    => @order.title.to_s.truncate(100),
          "SLIP_DATE" => Date.today.strftime("%Y%m%d")
        } ]
      }
    end

    def resolve_customer_code
      @order.client&.ecount_code.presence || @order.customer_name.to_s.truncate(20)
    end

    def resolve_product_code
      Product.find_by(name: @order.item_name)&.ecount_code.presence || @order.item_name.to_s.truncate(20)
    end

    def handle_failure(error)
      msg = error.message
      Rails.logger.error "[EcountApi::Slip] 전표 생성 실패: Order##{@order.id} — #{msg}"
      notify_admin(msg)
      { ok: false, error: msg }
    end

    def notify_admin(message)
      User.where(role: %w[admin manager]).find_each do |admin|
        key = "ecount_slip_failed_#{@order.id}"
        next if Notification.where(user: admin, notification_type: key).exists?

        Notification.create!(
          user:              admin,
          notifiable:        @order,
          notification_type: key,
          title:             "eCount 전표 생성 실패: #{@order.title}",
          body:              message
        )
      end
    end
  end
end
