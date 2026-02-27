# frozen_string_literal: true

module EcountApi
  # eCountERP SESSION_ID 발급 및 캐싱 관리
  # - Rails.cache에 23시간 캐싱 (eCount 세션 유효기간 24시간)
  # - 세션 만료 시 자동 재발급
  class AuthService < BaseService
    CACHE_KEY    = :ecount_session_id
    CACHE_EXPIRE = 23.hours

    def self.session_id
      new.fetch_session_id
    end

    def fetch_session_id
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached.present?

      id = login!
      Rails.cache.write(CACHE_KEY, id, expires_in: CACHE_EXPIRE)
      id
    end

    def invalidate!
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def login!
      cred = credentials
      body = {
        "COM_CODE"     => cred[:com_code],
        "USER_ID"      => cred[:user_id],
        "API_CERT_KEY" => cred[:api_cert_key],
        "LAN_TYPE"     => cred[:lan_type] || "ko",
        "ZONE"         => cred[:zone] || "A"
      }

      uri  = URI("#{BASE_URL}/OAPILogin")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = 30
      http.read_timeout = 30

      req              = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json; charset=UTF-8"
      req.body         = body.to_json

      resp   = http.request(req)
      parsed = JSON.parse(resp.body)
      code   = parsed.dig("RESPONSE", "HEADER", "RESULT_CODE")

      unless code == "0000"
        msg = parsed.dig("RESPONSE", "HEADER", "RESULT_MSG")
        raise EcountApi::AuthError, "eCount 로그인 실패 [#{code}]: #{msg}"
      end

      sid = parsed.dig("RESPONSE", "DATA1", 0, "SESSION_ID")
      raise EcountApi::AuthError, "SESSION_ID 없음" unless sid.present?

      Rails.logger.info "[EcountApi] 인증 성공 (SESSION_ID 발급)"
      sid
    end

    def credentials
      cred = Rails.application.credentials.dig(:ecount)
      raise EcountApi::AuthError, "eCount credentials 미설정 (bin/rails credentials:edit)" if cred.nil?
      cred
    end
  end
end
