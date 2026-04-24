require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # TailwindCSS CDN을 사용해 application.css는 비어있음. Link preload 헤더 비활성화로
  # "preloaded but not used" 경고 제거.
  config.action_view.preload_links_header = false

  # GZip compression — 응답 크기 50~70% 감소 (UAE 등 느린 네트워크에서 효과 큼)
  config.middleware.insert_after ActionDispatch::Static, Rack::Deflater

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # ISS-260: Mailer 설정 — Devise 비밀번호 재설정 메일 발송 가능하도록 활성화
  # host는 운영 도메인으로 고정 (Devise reset 링크가 example.com으로 안 가도록)
  mailer_host = ENV.fetch("MAILER_HOST", "cpoflow.ddtl.co.kr")
  config.action_mailer.default_url_options = { host: mailer_host, protocol: "https" }
  config.action_mailer.asset_host = "https://#{mailer_host}"

  # SMTP 자격정보 우선순위: ENV → Rails credentials.smtp → fallback
  smtp_user     = ENV["SMTP_USER_NAME"] || Rails.application.credentials.dig(:smtp, :user_name)
  smtp_password = ENV["SMTP_PASSWORD"]  || Rails.application.credentials.dig(:smtp, :password)
  smtp_address  = ENV["SMTP_ADDRESS"]   || Rails.application.credentials.dig(:smtp, :address) || "smtp.gmail.com"
  smtp_port     = (ENV["SMTP_PORT"]     || Rails.application.credentials.dig(:smtp, :port) || 587).to_i
  smtp_domain   = ENV["SMTP_DOMAIN"]    || Rails.application.credentials.dig(:smtp, :domain) || mailer_host

  if smtp_user.present? && smtp_password.present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      user_name:      smtp_user,
      password:       smtp_password,
      address:        smtp_address,
      port:           smtp_port,
      domain:         smtp_domain,
      authentication: :plain,
      enable_starttls_auto: true
    }
  else
    # 자격정보 미설정 시: 앱이 크래시하지 않도록 :test delivery_method로 fallback + 로그 경고
    # → 대표님이 bin/rails credentials:edit 또는 ENV(SMTP_USER_NAME/SMTP_PASSWORD 등)에 값을 주입해야 실제 발송됨.
    config.action_mailer.delivery_method = :test
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = false
    # 초기화 시점에는 Rails.logger 아직 없음 → $stderr로 경고 출력
    $stderr.puts "[ISS-260] SMTP credentials 미설정 — delivery_method=:test 로 fallback. " \
                 "비밀번호 재설정/알림 메일이 실제 발송되지 않습니다. " \
                 "자세한 설정 방법: docs/smtp-setup.md"
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
