# frozen_string_literal: true

# Production 에러 모니터링
# Sentry 연동 시 gem 'sentry-ruby' + 'sentry-rails' 추가 후 아래 주석 해제
#
# Sentry.init do |config|
#   config.dsn = Rails.application.credentials.dig(:sentry, :dsn)
#   config.breadcrumbs_logger = [:active_support_logger, :http_logger]
#   config.traces_sample_rate = 0.1
#   config.environment = Rails.env
# end

# 현재: Rails 기본 에러 리포팅 + 로그 강화
if Rails.env.production?
  Rails.application.configure do
    # 에러 발생 시 상세 로그 (request_id 포함)
    config.log_tags = [ :request_id ]

    # 미처리 예외 로깅
    config.exceptions_app = ->(env) {
      request = ActionDispatch::Request.new(env)
      exception = env["action_dispatch.exception"]
      Rails.logger.error "[UNHANDLED] #{exception.class}: #{exception.message} | Path: #{request.path} | IP: #{request.remote_ip}"
      raise exception
    }
  end
end
