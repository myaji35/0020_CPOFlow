# frozen_string_literal: true

module EcountApi
  # eCountERP API 공통 HTTP 클라이언트
  # - 지수 백오프 재시도 (최대 3회)
  # - 응답 파싱 + 에러 클래스 분기
  class BaseService
    # Zone 및 환경별 BASE_URL 자동 결정
    # - ENV["ECOUNT_BASE_URL"]이 있으면 최우선
    # - credentials.ecount.zone 기반 자동 선택 (BA = 한국 외 해외존, A = 한국)
    # - 테스트/실서버는 credentials.ecount.environment = "test" | "production"
    def self.base_url
      return ENV["ECOUNT_BASE_URL"] if ENV["ECOUNT_BASE_URL"].present?
      cred = Rails.application.credentials.dig(:ecount) || {}
      zone = (cred[:zone] || ENV["ECOUNT_ZONE"] || "BA").to_s.downcase
      env  = (cred[:environment] || ENV["ECOUNT_ENV"] || "test").to_s
      host = env == "production" ? "oapi#{zone}.ecount.com" : "sboapi#{zone}.ecount.com"
      "https://#{host}/OAPI/V2"
    end

    def self.login_base_url
      return ENV["ECOUNT_LOGIN_URL"] if ENV["ECOUNT_LOGIN_URL"].present?
      cred = Rails.application.credentials.dig(:ecount) || {}
      zone = (cred[:zone] || ENV["ECOUNT_ZONE"] || "BA").to_s.downcase
      env  = (cred[:environment] || ENV["ECOUNT_ENV"] || "test").to_s
      host = env == "production" ? "oapi#{zone}.ecount.com" : "sboapi#{zone}.ecount.com"
      "https://#{host}/OAPI/V2"
    end

    BASE_URL = "https://oapi.ecounterp.com/OAPI/V2"  # deprecated — use self.base_url
    TIMEOUT  = 30  # seconds

    MAX_RETRIES  = 3
    RETRY_DELAYS = [ 2, 4, 8 ].freeze  # 지수 백오프 (초)

    private

    def post(path, body)
      request_with_retry(:post, path, body)
    end

    def get(path, params = {})
      request_with_retry(:get, path, params)
    end

    def request_with_retry(method, path, payload)
      retries = 0
      begin
        response = send_request(method, path, payload)
        parse_response!(response)
      rescue EcountApi::RateLimitError
        raise  # 레이트 리밋은 재시도 안 함 — 다음 주기에 처리
      rescue EcountApi::AuthError
        raise  # 인증 오류는 호출자가 처리
      rescue EcountApi::ApiError
        retries += 1
        if retries <= MAX_RETRIES
          sleep(RETRY_DELAYS[retries - 1])
          retry
        end
        raise
      end
    end

    def send_request(method, path, payload)
      # eCount OAPI는 SESSION_ID를 반드시 query string으로 받음
      # body에만 넣으면 "Please login" (Status 500) 오류
      payload = payload.dup
      session = payload.delete("SESSION_ID") || payload.delete(:SESSION_ID)
      url = "#{self.class.base_url}#{path}"
      url += (url.include?("?") ? "&" : "?") + "SESSION_ID=#{session}" if session.present?

      uri  = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      if method == :post
        req      = Net::HTTP::Post.new(uri)
        req.body = payload.to_json
      else
        uri.query = [ uri.query, URI.encode_www_form(payload) ].compact.reject(&:empty?).join("&") if payload.any?
        req = Net::HTTP::Get.new(uri)
      end

      req["Content-Type"] = "application/json; charset=UTF-8"
      req["Accept"]       = "application/json"
      req["User-Agent"]   = "CPOFlow/1.0 (AtoZ2010 Inc)"

      http.request(req)
    end

    def parse_response!(response)
      body = JSON.parse(response.body)

      # 두 가지 응답 구조 지원:
      # 1) 실서버 일부: {"RESPONSE": {"HEADER": {"RESULT_CODE": "0000"}, "DATA1": [...]}}
      # 2) BA 테스트존: {"Status": "200", "Data": {"Result": [...], "TotalCnt": N, "QUANTITY_INFO": "..."}}
      if body["RESPONSE"]
        code = body.dig("RESPONSE", "HEADER", "RESULT_CODE")
        msg  = body.dig("RESPONSE", "HEADER", "RESULT_MSG")
        case code
        when "0000" then body.dig("RESPONSE", "DATA1") || []
        when "4001" then raise EcountApi::RateLimitError, "레이트 리밋 초과 (60req/min)"
        when "4010" then raise EcountApi::AuthError, "세션 만료 — 재인증 필요"
        else             raise EcountApi::ApiError, "eCount API 오류 [#{code}]: #{msg}"
        end
      elsif body["Status"].to_s == "200" && body["Data"]
        check_quota!(body.dig("Data", "QUANTITY_INFO"))
        body["Data"]  # 품목/재고 sync가 TotalCnt + Result 모두 필요
      else
        err = body.dig("Errors", 0, "Message") || body.dig("Error", "Message") || body.to_s[0, 200]
        status = body["Status"].to_s
        raise EcountApi::AuthError, "세션 만료 — 재인증 필요" if status == "4010"
        raise EcountApi::RateLimitError, "레이트 리밋 초과" if status == "4001"
        raise EcountApi::ApiError, "eCount API 오류 [#{status}]: #{err}"
      end
    end

    # QUANTITY_INFO: "시간당 연속 오류 제한 건수 : 0/30건, 1일 허용량 : 6/5000건"
    # 사용량 80% 초과 시 경고, 95% 초과 시 예외
    def check_quota!(info)
      return if info.blank?
      m = info.to_s.match(/1일\s*허용량\s*:\s*(\d+)\/(\d+)/)
      return unless m
      used, limit = m[1].to_i, m[2].to_i
      ratio = limit.zero? ? 0 : (used.to_f / limit)
      Rails.logger.info "[EcountApi] 일일 사용량 #{used}/#{limit} (#{(ratio * 100).round(1)}%)"
      if ratio >= 0.95
        raise EcountApi::RateLimitError, "일일 한도 95% 초과 (#{used}/#{limit}) — 내일까지 대기"
      elsif ratio >= 0.80
        Rails.logger.warn "[EcountApi] ⚠️ 일일 한도 80% 초과 — 호출 자제 필요 (#{used}/#{limit})"
      end
    end
  end

  # 커스텀 에러 클래스 계층
  class ApiError       < StandardError; end
  class AuthError      < ApiError; end
  class RateLimitError < ApiError; end
end
