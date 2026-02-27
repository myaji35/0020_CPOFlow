# frozen_string_literal: true

module EcountApi
  # eCountERP 품목 마스터 → CPOFlow products 테이블 Upsert 동기화
  # ecount_code 기준 매핑, 1페이지 50건씩 페이징
  class ProductSyncService < BaseService
    PAGE_SIZE = 50

    def sync!(sync_log)
      session = AuthService.session_id
      page    = 1
      total   = 0
      success = 0
      errors  = []

      loop do
        items = fetch_page(session, page)
        break if items.empty?

        items.each do |item|
          result = upsert_product(item)
          if result[:ok]
            success += 1
          else
            errors << { code: item["PROD_CD"], name: item["PROD_DES"], error: result[:error] }
          end
          total += 1
        end

        sync_log.update_columns(
          total_count:   total,
          success_count: success,
          error_count:   errors.size
        )

        sleep(1)  # 레이트 리밋 방어 (60req/min)
        page += 1
      end

      Rails.logger.info "[EcountApi::ProductSync] #{success}/#{total} 완료, 오류 #{errors.size}건"
      { total: total, success: success, errors: errors }
    end

    private

    def fetch_page(session, page)
      post("/Inventory/BasicInfo/GetBasicInfoList", {
        "SESSION_ID" => session,
        "PAGE_COND"  => { "PAGE_SIZE" => PAGE_SIZE, "PAGE_NUM" => page }
      })
    rescue EcountApi::AuthError
      # 세션 만료 시 재인증 후 1회 재시도
      EcountApi::AuthService.new.invalidate!
      session = EcountApi::AuthService.session_id
      post("/Inventory/BasicInfo/GetBasicInfoList", {
        "SESSION_ID" => session,
        "PAGE_COND"  => { "PAGE_SIZE" => PAGE_SIZE, "PAGE_NUM" => page }
      })
    end

    def upsert_product(item)
      attrs = {
        name:             item["PROD_DES"].to_s.strip,
        description:      item["SIZE_DES"].to_s.strip,
        unit:             item["UNIT"].to_s.strip,
        category:         item["CLASS_CD"].to_s.strip,
        unit_price:       item["PRICE"].to_f,
        currency:         item["CURR_CD"].presence || "USD",
        active:           item["USE_YN"] == "Y",
        ecount_synced_at: Time.current
      }

      product = Product.find_or_initialize_by(ecount_code: item["PROD_CD"])
      product.assign_attributes(attrs)
      product.save!
      { ok: true }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error: e.message }
    rescue StandardError => e
      { ok: false, error: "예외: #{e.class} — #{e.message}" }
    end
  end
end
