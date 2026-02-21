# frozen_string_literal: true

# Lockbox: AES-256-GCM encryption for sensitive fields (Gmail OAuth tokens)
# Key is derived from Rails secret_key_base in development.
# In production: set LOCKBOX_MASTER_KEY env var or Rails credentials.
Lockbox.master_key = ENV.fetch("LOCKBOX_MASTER_KEY") {
  # Development fallback: derive from secret_key_base (NOT for production)
  Rails.application.secret_key_base[0..63]
}
