# frozen_string_literal: true

# ISS-354 Phase 2 Wave 1 — T0
# - orders.mention_worst_intent: 카드 좌측 스트라이프/뱃지용 worst-intent 캐시
# - notifications.sent_by_user_id: B3 결정 — 발신자 식별 (호버 카드, 리마인드 권한)
# - notifications.reminded_at: 24h cooldown 기준 시각 (리마인드 발송 시 set)
class AddPhase2MentionColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :mention_worst_intent, :integer, default: 0, null: false

    add_column :notifications, :sent_by_user_id, :integer
    add_column :notifications, :reminded_at, :datetime

    add_index :notifications, :sent_by_user_id
    add_index :notifications, :reminded_at
  end
end
