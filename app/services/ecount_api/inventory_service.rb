# frozen_string_literal: true

module EcountApi
  # eCountERP 실시간 재고 조회
  # Rails.cache에 10분 캐싱 (Redis 없는 환경: MemoryStore)
  class InventoryService < BaseService
    CACHE_TTL = 10.minutes

    def self.stock_for(ecount_code)
      new.fetch_stock(ecount_code)
    end

    def fetch_stock(ecount_code)
      return nil if ecount_code.blank?

      cache_key = "ecount_stock_#{ecount_code}"
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_from_api(ecount_code)
      end
    end

    private

    def fetch_from_api(ecount_code)
      session = AuthService.session_id
      data    = get("/Inventory/InventoryStatusInfo/GetInfo",
                    "SESSION_ID" => session, "PROD_CD" => ecount_code)
      Array(data).dig(0, "CURR_QTY").to_i
    rescue EcountApi::ApiError => e
      Rails.logger.warn "[EcountApi::Inventory] 재고 조회 실패 [#{ecount_code}]: #{e.message}"
      nil  # 실패 시 nil 반환 → UI에서 "조회 불가" 표시
    end
  end
end
