# frozen_string_literal: true

# i18n 환경별 기본 locale 설정
# - development: 한국어 (대표님 확인용)
# - production: 영어 (해외 사용자용)
Rails.application.configure do
  config.i18n.available_locales = [ :en, :ko, :ar ]

  config.i18n.default_locale = if Rails.env.production?
    :en
  else
    :ko
  end

  config.i18n.fallbacks = { ko: :en, ar: :en }
end
