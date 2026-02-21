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
      account.assign_attributes(
        gmail_access_token:  client.access_token,
        gmail_refresh_token: client.refresh_token || account.gmail_refresh_token,
        token_expires_at:    Time.at(client.expires_at.to_i),
        oauth_scope:         EmailAccount::GMAIL_SCOPES.join(" "),
        connected:           true
      )
      account.save!

      redirect_to settings_root_path, notice: "Gmail account '#{email}' connected successfully!"
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
    redirect_to settings_root_path, notice: "Gmail account disconnected."
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
    client.authorization = Signet::OAuth2::Client.new(access_token: access_token)
    profile = client.get_user_profile("me")
    profile.email_address
  rescue Google::Apis::Error
    "unknown@gmail.com"
  end
end
