# frozen_string_literal: true

# 사용자 RFQ 피드백 저장 모델
# verdict: "confirmed" (RFQ 맞음) | "rejected" (RFQ 아님)
class RfqFeedback < ApplicationRecord
  belongs_to :order
  belongs_to :user

  validates :verdict, inclusion: { in: %w[confirmed rejected reverted] }
  validates :ai_score, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true

  scope :confirmed, -> { where(verdict: "confirmed") }
  scope :rejected,  -> { where(verdict: "rejected") }
  scope :recent,    -> { order(created_at: :desc) }
  scope :with_ai_score, -> { where.not(ai_score: nil) }

  # AI 판정과 사용자 verdict 가 일치하는지 (AI 가 RFQ 라고 한 경우만 평가)
  # ai_score >= 0.5 → AI 는 RFQ 라고 판정
  # verdict == "confirmed" → 사용자가 RFQ 라고 확정
  def ai_correct?
    return nil if ai_score.nil?
    ai_says_rfq = ai_score >= 0.5
    user_says_rfq = verdict == "confirmed"
    ai_says_rfq == user_says_rfq
  end
end
