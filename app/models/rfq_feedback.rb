# frozen_string_literal: true

# 사용자 RFQ 피드백 저장 모델
# verdict: "confirmed" (RFQ 맞음) | "rejected" (RFQ 아님)
class RfqFeedback < ApplicationRecord
  belongs_to :order
  belongs_to :user

  validates :verdict, inclusion: { in: %w[confirmed rejected] }

  scope :confirmed, -> { where(verdict: "confirmed") }
  scope :rejected,  -> { where(verdict: "rejected") }
  scope :recent,    -> { order(created_at: :desc) }
end
