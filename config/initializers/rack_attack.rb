# frozen_string_literal: true

# Rack::Attack — 로그인 무차별 공격 방어 + API 레이트 리밋
class Rack::Attack
  ### Throttle: 로그인 시도 제한 ###
  # 같은 IP에서 5분 내 20회 로그인 시도 → 차단
  throttle("logins/ip", limit: 20, period: 5.minutes) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # 같은 이메일로 5분 내 10회 로그인 시도 → 차단
  throttle("logins/email", limit: 10, period: 5.minutes) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  ### Throttle: API 요청 제한 ###
  # 같은 IP에서 1분 내 120회 요청 → 차단
  throttle("req/ip", limit: 120, period: 1.minute) do |req|
    req.ip unless req.path.start_with?("/assets", "/up")
  end

  ### 차단 시 응답 ###
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    [
      429,
      {
        "Content-Type" => "text/plain",
        "Retry-After" => retry_after.to_s
      },
      ["Too many requests. Please retry after #{retry_after} seconds.\n"]
    ]
  end
end
