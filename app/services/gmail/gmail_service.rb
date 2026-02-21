# frozen_string_literal: true

module Gmail
  # Wraps Google::Apis::GmailV1 with token refresh and error handling.
  # Usage:
  #   svc = Gmail::GmailService.new(email_account)
  #   messages = svc.fetch_recent_messages(max: 50)
  class GmailService
    SCOPES = EmailAccount::GMAIL_SCOPES

    def initialize(email_account)
      @account = email_account
      @gmail   = build_client
    end

    # Fetch recent message stubs (id + threadId only)
    def fetch_recent_message_ids(max: 50, query: nil)
      refresh_token_if_needed!
      response = @gmail.list_user_messages(
        "me",
        max_results: max,
        q: query
      )
      response.messages || []
    rescue Google::Apis::AuthorizationError
      handle_auth_error
      []
    rescue Google::Apis::Error => e
      Rails.logger.error "[GmailService] API error: #{e.message}"
      []
    end

    # Fetch a full message by Gmail message ID
    def fetch_message(gmail_message_id)
      refresh_token_if_needed!
      @gmail.get_user_message("me", gmail_message_id, format: "full")
    rescue Google::Apis::Error => e
      Rails.logger.error "[GmailService] fetch_message error: #{e.message}"
      nil
    end

    # Fetch messages with full details (batched for efficiency)
    def fetch_recent_messages(max: 30, query: nil)
      ids = fetch_recent_message_ids(max: max, query: query)
      return [] if ids.empty?

      ids.map { |stub| fetch_message(stub.id) }.compact
    end

    # Parse a Gmail message into a plain Ruby hash
    def parse_message(msg)
      return nil if msg.nil?

      headers = (msg.payload&.headers || []).each_with_object({}) do |h, hash|
        hash[h.name.downcase] = h.value
      end

      {
        id:          msg.id,
        thread_id:   msg.thread_id,
        subject:     headers["subject"] || "(no subject)",
        from:        headers["from"] || "",
        to:          headers["to"] || "",
        date:        parse_date(headers["date"]),
        snippet:     msg.snippet || "",
        body:        extract_body(msg.payload),
        labels:      msg.label_ids || [],
        unread:      msg.label_ids&.include?("UNREAD") || false
      }
    end

    # Mark message as read in Gmail
    def mark_as_read(gmail_message_id)
      refresh_token_if_needed!
      @gmail.modify_user_message(
        "me",
        gmail_message_id,
        Google::Apis::GmailV1::ModifyMessageRequest.new(remove_label_ids: ["UNREAD"])
      )
    rescue Google::Apis::Error => e
      Rails.logger.error "[GmailService] mark_as_read error: #{e.message}"
    end

    private

    def build_client
      client = Google::Apis::GmailV1::GmailService.new
      client.authorization = build_credentials
      client
    end

    def build_credentials
      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id:     Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        scope:         SCOPES,
        access_token:  @account.gmail_access_token,
        refresh_token: @account.gmail_refresh_token,
        expires_at:    @account.token_expires_at
      )
      credentials
    end

    def refresh_token_if_needed!
      return unless @account.needs_refresh?

      credentials = build_credentials
      credentials.refresh!

      @account.update!(
        gmail_access_token: credentials.access_token,
        token_expires_at:   credentials.expires_at
      )

      # Rebuild client with fresh token
      @gmail = build_client
    rescue Signet::AuthorizationError => e
      Rails.logger.error "[GmailService] Token refresh failed: #{e.message}"
      @account.update!(connected: false)
      raise
    end

    def handle_auth_error
      @account.update!(connected: false)
      Rails.logger.warn "[GmailService] Auth error — account #{@account.email} disconnected"
    end

    def extract_body(payload)
      return "" unless payload

      # Prefer text/plain, fallback to text/html
      if payload.mime_type == "text/plain" && payload.body&.data
        Base64.urlsafe_decode64(payload.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      elsif payload.parts
        plain = payload.parts.find { |p| p.mime_type == "text/plain" }
        html  = payload.parts.find { |p| p.mime_type == "text/html" }
        part  = plain || html
        return "" unless part&.body&.data
        Base64.urlsafe_decode64(part.body.data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace)
      else
        payload.body&.data ? Base64.urlsafe_decode64(payload.body.data).force_encoding("UTF-8") : ""
      end
    rescue ArgumentError
      ""
    end

    def parse_date(date_str)
      Time.parse(date_str) rescue Time.current
    end
  end
end
