# frozen_string_literal: true

module EcountApi
  # eCount OAPI 품목 마스터 → CPOFlow products 테이블 Upsert 동기화
  # 엔드포인트: /InventoryBasic/GetBasicProductsList (검증 완료 2026-04-15)
  # 단일 호출로 전체 수신 (TotalCnt ≈ 10,000건, 1.4s, 18MB)
  class ProductSyncService < BaseService
    CHUNK_SIZE = 500  # DB upsert chunk

    def sync!(sync_log)
      started = Time.current
      sync_log.update_columns(started_at: started, status: 1) if sync_log

      items = fetch_all
      total = items.size
      Rails.logger.info "[EcountApi::ProductSync] #{total}건 수신 (#{(Time.current - started).round(2)}s)"

      success = 0
      errors  = []

      items.each_slice(CHUNK_SIZE).with_index do |chunk, idx|
        rows = chunk.map { |item| product_attrs(item) }.compact
        begin
          Product.upsert_all(rows, unique_by: :ecount_code, update_only: UPDATE_COLS)
          success += rows.size
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
          chunk.each { |item| upsert_one(item, errors) { success += 1 } }
        end

        sync_log&.update_columns(
          total_count:   total,
          success_count: success,
          error_count:   errors.size
        )
      end

      sync_log&.update_columns(
        status: errors.empty? ? 2 : 3,
        completed_at: Time.current,
        error_details: errors.first(50).to_json
      )

      Rails.logger.info "[EcountApi::ProductSync] 완료: #{success}/#{total}, 오류 #{errors.size}건"
      { total: total, success: success, errors: errors }
    end

    UPDATE_COLS = %i[name description unit category unit_price currency active ecount_synced_at updated_at].freeze

    private

    def fetch_all
      session = AuthService.session_id
      data = post("/InventoryBasic/GetBasicProductsList", {
        "SESSION_ID" => session,
        "PROD_CD"    => ""
      })
      extract_result(data)
    rescue EcountApi::AuthError
      EcountApi::AuthService.new.invalidate!
      session = EcountApi::AuthService.session_id
      data = post("/InventoryBasic/GetBasicProductsList", {
        "SESSION_ID" => session,
        "PROD_CD"    => ""
      })
      extract_result(data)
    end

    # BaseService.parse_response! 는 RESPONSE.DATA1 경로를 기대하나
    # BA 존은 Data.Result 를 쓰므로 수동 추출 대비 (현재는 parse_response!가 반환한 구조 수용)
    def extract_result(data)
      return data if data.is_a?(Array)
      result = data.is_a?(Hash) ? (data["Result"] || data.dig("Data", "Result")) : nil
      Array(result)
    end

    def product_attrs(item)
      code = item["PROD_CD"].to_s.strip
      return nil if code.blank?
      now = Time.current
      {
        ecount_code:      code,
        name:             item["PROD_DES"].to_s.strip,
        description:      item["SIZE_DES"].to_s.strip,
        unit:             item["UNIT"].to_s.strip,
        category:         item["CLASS_CD"].to_s.strip,
        unit_price:       item["IN_PRICE"].to_f,
        currency:         item["CURR_CD"].presence || "USD",
        active:           item["USE_YN"] != "N",
        ecount_synced_at: now,
        created_at:       now,
        updated_at:       now
      }
    end

    def upsert_one(item, errors)
      product = Product.find_or_initialize_by(ecount_code: item["PROD_CD"])
      product.assign_attributes(product_attrs(item).except(:ecount_code, :created_at))
      product.save!
      yield if block_given?
    rescue ActiveRecord::RecordInvalid => e
      errors << { code: item["PROD_CD"], name: item["PROD_DES"], error: e.message }
    rescue StandardError => e
      errors << { code: item["PROD_CD"], name: item["PROD_DES"], error: "예외: #{e.class} — #{e.message}" }
    end
  end
end
