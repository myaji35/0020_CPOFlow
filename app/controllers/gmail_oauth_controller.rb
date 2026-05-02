# frozen_string_literal: true

# Handles Google OAuth2 flow for Gmail integration.
# Flow: /settings → Connect Gmail → Google consent screen → callback here → save tokens
class GmailOauthController < ApplicationController
  # Step 1: Redirect user to Google's consent screen
  def authorize
    client = google_auth_client
    redirect_to client.authorization_uri.to_s, allow_other_host: true
  end

  # Step 2: Google redirects back with ?code=... or ?error=...
  def callback
    if params[:error].present?
      redirect_to settings_root_path, alert: "Google authorization failed: #{params[:error]}"
      return
    end

    code = params[:code]
    unless code.present?
      redirect_to settings_root_path, alert: "No authorization code received."
      return
    end

    begin
      client = google_auth_client
      client.code = code
      client.fetch_access_token!

      email = fetch_gmail_email(client.access_token)

      # ISS-344 (C): user별 분리 — 같은 email을 다른 user가 각자 connect할 수 있게
      # 기존 레코드는 (email, user_id) 조합으로만 매칭. user_id 덮어쓰기 방지.
      account = EmailAccount.find_or_initialize_by(email: email, user: current_user)

      # refresh_token: Google는 최초 동의 시에만 발급 → 기존 값 보존
      new_refresh_token = client.refresh_token.presence || (account.persisted? ? account.gmail_refresh_token : nil)

      account.gmail_access_token  = client.access_token
      account.gmail_refresh_token = new_refresh_token if new_refresh_token.present?
      account.token_expires_at    = Time.at(client.expires_at.to_i)
      account.oauth_scope         = EmailAccount::GMAIL_SCOPES.join(" ")
      account.connected           = true
      account.save!

      redirect_to settings_root_path, notice: t("settings.gmail.connect_success")
    rescue Signet::AuthorizationError => e
      Rails.logger.error "[GmailOauth] Token exchange failed: #{e.message}"
      redirect_to settings_root_path, alert: "Failed to connect Gmail. Please try again."
    rescue Google::Apis::Error => e
      Rails.logger.error "[GmailOauth] Google API error: #{e.message}"
      redirect_to settings_root_path, alert: "Google API error. Please try again."
    end
  end

  # Step 3: Disconnect a Gmail account
  # ISS-344 (B): refresh_token까지 제거 + Google revoke API 호출 → 완전 disconnect
  def disconnect
    account = current_user.email_accounts.find(params[:id])

    # Google 서버에 token revoke 요청 (best-effort, 실패해도 DB 정리는 진행)
    revoke_google_token(account.gmail_refresh_token.presence || account.gmail_access_token)

    account.update!(
      connected: false,
      gmail_access_token: nil,
      gmail_refresh_token: nil,
      token_expires_at: nil,
      oauth_scope: nil
    )
    redirect_to settings_root_path, notice: t("settings.gmail.disconnect_success")
  rescue ActiveRecord::RecordNotFound
    redirect_to settings_root_path, alert: "Account not found."
  end

  private

  def google_auth_client
    Signet::OAuth2::Client.new(
      client_id:              Rails.application.credentials.dig(:google, :client_id),
      client_secret:          Rails.application.credentials.dig(:google, :client_secret),
      authorization_uri:      "https://accounts.google.com/o/oauth2/auth",
      token_credential_uri:   "https://oauth2.googleapis.com/token",
      scope:                  EmailAccount::GMAIL_SCOPES,
      redirect_uri:           gmail_oauth_callback_url,
      access_type:            "offline",
      prompt:                 "consent"   # force refresh_token on every consent
    )
  end

  # ISS-344 (B): Google 측 권한 revoke. Google 계정 → 보안 → 타사 앱 목록에서도 제거됨.
  # 다음 Connect 시 동의 화면이 다시 표시됨.
  def revoke_google_token(token)
    return if token.blank?
    require "net/http"
    uri = URI("https://oauth2.googleapis.com/revoke")
    res = Net::HTTP.post_form(uri, token: token)
    Rails.logger.info "[GmailOauth] revoke response: #{res.code}"
  rescue => e
    Rails.logger.warn "[GmailOauth] revoke failed (continuing): #{e.message}"
  end

  def fetch_gmail_email(access_token)
    client = Google::Apis::GmailV1::GmailService.new
    client.authorization = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         EmailAccount::GMAIL_SCOPES,
      access_token:  access_token
    )
    profile = client.get_user_profile("me")
    profile.email_address
  rescue Google::Apis::Error, StandardError => e
    Rails.logger.error "[GmailOauth] fetch_gmail_email error: #{e.message}"
    "unknown@gmail.com"
  end
end
