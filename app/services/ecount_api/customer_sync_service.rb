# frozen_string_literal: true

module EcountApi
  # eCountERP 거래처 → CPOFlow clients / suppliers Upsert 동기화
  # AR_CD_TYPE: "1"=매출처(Client), "2"=매입처(Supplier), "3"=양방향
  class CustomerSyncService < BaseService
    PAGE_SIZE = 50

    CUSTOMER_TYPE_MAP = {
      "1" => :client,
      "2" => :supplier,
      "3" => :both
    }.freeze

    def sync!(sync_log)
      session = AuthService.session_id
      page    = 1
      total   = 0
      success = 0
      errors  = []

      loop do
        customers = fetch_page(session, page)
        break if customers.empty?

        customers.each do |cust|
          result = upsert_customer(cust)
          success += result[:count]
          errors.concat(result[:errors])
          total += 1
        end

        sync_log.update_columns(
          total_count:   total,
          success_count: success,
          error_count:   errors.size
        )

        sleep(1)
        page += 1
      end

      Rails.logger.info "[EcountApi::CustomerSync] #{success}/#{total} 완료, 오류 #{errors.size}건"
      { total: total, success: success, errors: errors }
    end

    private

    def fetch_page(session, page)
      post("/BaseInfo/Customer/GetCustomerList", {
        "SESSION_ID" => session,
        "PAGE_COND"  => { "PAGE_SIZE" => PAGE_SIZE, "PAGE_NUM" => page }
      })
    rescue EcountApi::AuthError
      EcountApi::AuthService.new.invalidate!
      session = EcountApi::AuthService.session_id
      post("/BaseInfo/Customer/GetCustomerList", {
        "SESSION_ID" => session,
        "PAGE_COND"  => { "PAGE_SIZE" => PAGE_SIZE, "PAGE_NUM" => page }
      })
    end

    def upsert_customer(cust)
      type   = CUSTOMER_TYPE_MAP[cust["AR_CD_TYPE"]] || :supplier
      count  = 0
      errors = []
      attrs  = build_attrs(cust)

      if type == :client || type == :both
        r = save_record(Client, cust["AR_CD"], attrs)
        r[:ok] ? (count += 1) : errors << r[:error_entry]
      end

      if type == :supplier || type == :both
        r = save_record(Supplier, cust["AR_CD"], attrs)
        r[:ok] ? (count += 1) : errors << r[:error_entry]
      end

      { count: count, errors: errors }
    end

    def build_attrs(cust)
      {
        name:             cust["AR_NM"].to_s.strip,
        country:          cust["NAT_CD"].to_s.strip,
        contact_email:    cust["EMAIL"].to_s.strip,
        contact_phone:    cust["TEL"].to_s.strip,
        notes:            cust["REMARK"].to_s.strip,
        ecount_synced_at: Time.current
      }
    end

    def save_record(klass, ecount_code, attrs)
      rec = klass.find_or_initialize_by(ecount_code: ecount_code)
      rec.assign_attributes(attrs)
      rec.save!
      { ok: true }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error_entry: { code: ecount_code, model: klass.name, error: e.message } }
    rescue StandardError => e
      { ok: false, error_entry: { code: ecount_code, model: klass.name, error: "#{e.class}: #{e.message}" } }
    end
  end
end
