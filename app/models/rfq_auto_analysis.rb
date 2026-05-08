# frozen_string_literal: true

# LAB / RFQ Auto — Order 단위 자동 분석 영구 기록.
# 단계: step1(첨부 분류) → step2(품목 + 11항목 체크) → step3(Task 후보) → step4(공급사) → step5(요약)
class RfqAutoAnalysis < ApplicationRecord
  STATUSES  = %w[pending running completed failed].freeze
  FEEDBACKS = %w[correct wrong partial].freeze

  belongs_to :order
  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :feedback, inclusion: { in: FEEDBACKS }, allow_nil: true

  scope :recent, -> { order("rfq_auto_analyses.created_at DESC") }
  scope :for_order, ->(order_id) { where(order_id: order_id) }

  # JSON 컬럼 헬퍼 — 빈 해시 fallback
  def steps_data
    parsed = steps.present? ? (JSON.parse(steps) rescue {}) : {}
    parsed.is_a?(Hash) ? parsed : {}
  end

  def summary_data
    parsed = summary.present? ? (JSON.parse(summary) rescue {}) : {}
    parsed.is_a?(Hash) ? parsed : {}
  end

  def step_result(key)
    steps_data[key.to_s] || {}
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def duration_seconds
    return nil unless started_at && completed_at
    (completed_at - started_at).round(2)
  end
end
