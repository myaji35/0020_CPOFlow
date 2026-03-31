# frozen_string_literal: true

# Paperclip 방식 Claude CLI OAuth 토큰 자동 감지
#
# 우선순위:
#   1. AppSetting(DB) — 관리자가 직접 입력한 API 키
#   2. Claude CLI OAuth 토큰 (~/.claude/credentials.json)
#   3. ANTHROPIC_API_KEY 환경변수
#   4. Rails credentials 파일
#
# Usage:
#   result = ClaudeTokenResolver.resolve
#   result[:key]      # => "sk-ant-..." 또는 OAuth 토큰
#   result[:source]   # => :db, :claude_cli, :env, :credentials
#   result[:auth]     # => :api_key 또는 :bearer (호출 방식 구분)
#
#   ClaudeTokenResolver.configured?  # => true/false
#   ClaudeTokenResolver.status       # => { source: :claude_cli, masked: "eyJhb...xyz" }
class ClaudeTokenResolver
  CLAUDE_CONFIG_DIR = ENV.fetch("CLAUDE_CONFIG_DIR", File.join(Dir.home, ".claude"))
  CREDENTIALS_FILES = [".credentials.json", "credentials.json"].freeze

  class << self
    def resolve
      # 1. DB (AppSetting)
      db_key = AppSetting.get("anthropic_api_key").presence
      return { key: db_key, source: :db, auth: :api_key } if db_key

      # 2. Claude CLI OAuth 토큰
      cli_token = read_claude_cli_token
      return { key: cli_token, source: :claude_cli, auth: :bearer } if cli_token

      # 3. 환경변수
      env_key = ENV["ANTHROPIC_API_KEY"].presence
      return { key: env_key, source: :env, auth: :api_key } if env_key

      # 4. Rails credentials
      cred_key = Rails.application.credentials.dig(:anthropic, :api_key).presence
      return { key: cred_key, source: :credentials, auth: :api_key } if cred_key

      nil
    end

    def configured?
      resolve.present?
    end

    def status
      result = resolve
      return { source: nil, configured: false } unless result

      {
        source: result[:source],
        auth: result[:auth],
        configured: true,
        masked: mask_token(result[:key])
      }
    end

    # Anthropic SDK 클라이언트 생성 헬퍼
    def create_client
      result = resolve
      return nil unless result

      case result[:auth]
      when :bearer
        # Claude CLI OAuth 토큰 → SDK의 auth_token (Bearer 인증)
        Anthropic::Client.new(auth_token: result[:key])
      else
        Anthropic::Client.new(api_key: result[:key])
      end
    end

    # Net::HTTP용 헤더 생성 (rfq_reply_draft_service 등에서 사용)
    def auth_headers
      result = resolve
      return {} unless result

      base = {
        "Content-Type"      => "application/json",
        "anthropic-version" => "2023-06-01"
      }

      case result[:auth]
      when :bearer
        base.merge("Authorization" => "Bearer #{result[:key]}")
      else
        base.merge("x-api-key" => result[:key])
      end
    end

    private

    def read_claude_cli_token
      CREDENTIALS_FILES.each do |filename|
        path = File.join(CLAUDE_CONFIG_DIR, filename)
        next unless File.exist?(path)

        begin
          raw = File.read(path)
          parsed = JSON.parse(raw)
          token = parsed.dig("claudeAiOauth", "accessToken")
          return token if token.is_a?(String) && token.present?
        rescue JSON::ParserError, Errno::EACCES => e
          Rails.logger.warn "[ClaudeTokenResolver] #{filename} 읽기 실패: #{e.message}"
        end
      end

      nil
    end

    def mask_token(token)
      return nil unless token
      if token.length > 12
        "#{token[0..5]}...#{token[-6..]}"
      else
        "***"
      end
    end
  end
end
