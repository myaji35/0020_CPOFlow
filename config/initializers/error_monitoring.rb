# frozen_string_literal: true

# ISS-316: Sentry 도입으로 이 파일의 커스텀 예외 로깅은 제거.
# Sentry 설정은 config/initializers/sentry.rb 참조.
# Rails 기본 에러 리포팅은 그대로 작동 (log_tags 등 config/environments/production.rb 설정).
