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
      uri  = URI("#{self.class.base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      if method == :post
        req      = Net::HTTP::Post.new(uri)
        req.body = payload.to_json
      else
        uri.query = URI.encode_www_form(payload) if payload.any?
        req = Net::HTTP::Get.new(uri)
      end

      req["Content-Type"] = "application/json; charset=UTF-8"
      req["Accept"]       = "application/json"

      http.request(req)
    end

    def parse_response!(response)
      body = JSON.parse(response.body)
      code = body.dig("RESPONSE", "HEADER", "RESULT_CODE")
      msg  = body.dig("RESPONSE", "HEADER", "RESULT_MSG")

      case code
      when "0000" then body.dig("RESPONSE", "DATA1") || []
      when "4001" then raise EcountApi::RateLimitError, "레이트 리밋 초과 (60req/min)"
      when "4010" then raise EcountApi::AuthError, "세션 만료 — 재인증 필요"
      else             raise EcountApi::ApiError, "eCount API 오류 [#{code}]: #{msg}"
      end
    end
  end

  # 커스텀 에러 클래스 계층
  class ApiError       < StandardError; end
  class AuthError      < ApiError; end
  class RateLimitError < ApiError; end
end
