# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # 키로 값 조회 (nil-safe)
  def self.get(key)
    find_by(key: key)&.value
  end

  # 키로 값 저장/갱신 (upsert)
  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
    record
  end

  # Google Chat Webhook URL
  def self.google_chat_webhook_url
    get("google_chat_webhook_url").presence
  end
end
