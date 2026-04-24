# frozen_string_literal: true

# ISS-278: Google Chat webhook 실패 시 자동 재시도.
#
# 실행 흐름:
#   1) webhook_url / payload 해시를 인자로 받아 Faraday POST
#   2) 5xx / 429 / Timeout → retry_on이 exponential backoff로 재시도
#   3) 4xx(401/403/404) → raise하면 무한 재시도되므로 로그 + 종료
#   4) 최종 실패 → Rails.logger.error + (옵션) 관리자 Notification
#
# GoogleChatService.notify_later 에서 호출됨.
class GoogleChatNotifyJob < ApplicationJob
  queue_as :default

  # 네트워크성 에러는 지수 백오프로 재시도 (30s → 1m → 2m → 4m → 8m)
  retry_on Faraday::ServerError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 5

  # 메시지 포맷/자격증명 에러는 재시도 무의미 — 즉시 버림 + 로그
  discard_on Faraday::ClientError do |job, error|
    Rails.logger.error "[ISS-278][GoogleChatNotifyJob] 4xx 버림: #{error.response&.dig(:status)} #{error.message} payload_keys=#{job.arguments.first&.keys}"
  end

  def perform(payload, webhook_url)
    return if webhook_url.blank?

    response = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = payload.to_json
      req.options.timeout = 10
      req.options.open_timeout = 5
    end

    unless response.success?
      # 5xx는 Faraday raise_error middleware가 없으면 success?만 false → 강제 raise로 retry 유도
      if response.status.to_i >= 500 || response.status.to_i == 429
        raise Faraday::ServerError.new("Google Chat #{response.status}", response)
      else
        Rails.logger.warn "[ISS-278][GoogleChatNotifyJob] 실패 status=#{response.status} body=#{response.body.to_s.truncate(200)}"
      end
    end
  end
end
