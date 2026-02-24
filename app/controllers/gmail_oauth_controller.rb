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

      account = current_user.email_accounts.find_or_initialize_by(email: email)
      new_refresh_token = client.refresh_token.presence || (account.persisted? ? account.gmail_refresh_token : nil)

      if account.new_record?
        account.assign_attributes(
          gmail_access_token:  client.access_token,
          gmail_refresh_token: new_refresh_token,
          token_expires_at:    Time.at(client.expires_at.to_i),
          oauth_scope:         EmailAccount::GMAIL_SCOPES.join(" "),
          connected:           true
        )
        account.save!
      else
        # force-write encrypted columns via direct attribute assignment + save
        account.gmail_access_token  = client.access_token
        account.gmail_refresh_token = new_refresh_token if new_refresh_token.present?
        account.token_expires_at    = Time.at(client.expires_at.to_i)
        account.oauth_scope         = EmailAccount::GMAIL_SCOPES.join(" ")
        account.connected           = true
        account.save!
        # Lockbox 암호화 컬럼 save 시 connected 변경이 누락되는 경우 대비
        account.update_column(:connected, true) unless account.connected?
      end

      redirect_to settings_root_path, notice: t("settings.gmail.connect_success")
    rescue Signet::AuthorizationError => e
      Rails.logger.error "[GmailOauth] Token exchange failed: #{e.message}"
      redirect_to settings_root_path, alert: "Failed to connect Gmail. Please try again."
    rescue Google::Apis::Error => e
      Rails.logger.error "[GmailOauth] Google API error: #{e.message}"
      redirect_to settings_root_path, alert: "Google API error. Please try again."
    end
  end

  # Step 3 (optional): Disconnect a Gmail account
  def disconnect
    account = current_user.email_accounts.find(params[:id])
    account.update!(connected: false, gmail_access_token: nil)
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
