# frozen_string_literal: true

# ISS-316: Sentry 에러 모니터링
# DSN이 없으면 silent skip (로컬/CI 환경 안전)
return unless ENV["SENTRY_DSN"].present?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = false  # 개인정보 전송 금지
  config.traces_sample_rate = 0.1  # 10% APM 샘플링
  config.profiles_sample_rate = 0.0  # 프로파일링 비활성 (비용 절감)
  config.environment = Rails.env
  config.release = ENV["KAMAL_VERSION"] || "unknown"

  # 노이즈 필터링 — 404 및 봇 트래픽 제외
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound",
    "ActionController::InvalidAuthenticityToken"
  ]
end
