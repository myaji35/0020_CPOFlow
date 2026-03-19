# frozen_string_literal: true

class AgentInsight < ApplicationRecord
  belongs_to :order
  belongs_to :supplier, optional: true

  enum :severity, { info: 0, warning: 1, alert: 2 }
  enum :insight_type, {
    price_comparison: "price_comparison",
    supplier_risk:    "supplier_risk",
    due_date_risk:    "due_date_risk",
    cost_saving:      "cost_saving"
  }

  validates :insight_type, :title, presence: true

  scope :active, -> {
    where(dismissed: false)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
  scope :for_order, ->(order_id) { where(order_id: order_id).active.order(severity: :desc) }
  scope :for_dashboard, -> {
    active.where(severity: [:warning, :alert]).order(severity: :desc, created_at: :desc).limit(5)
  }

  # 동일 타입의 기존 Insight가 있으면 교체 (중복 방지)
  def self.upsert_for(order:, insight_type:, attrs: {})
    existing = find_by(order: order, insight_type: insight_type, dismissed: false)
    if existing
      existing.update!(attrs)
      existing
    else
      create!(attrs.merge(order: order, insight_type: insight_type))
    end
  end
end
