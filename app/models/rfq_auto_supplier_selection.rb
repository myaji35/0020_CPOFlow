# frozen_string_literal: true

# LAB / RFQ Auto D-5 — 분석 결과 공급사 중 사용자가 선택한 후보.
# 같은 분석 내 (item_idx, supplier_name) unique → 체크박스 토글로 작동.
class RfqAutoSupplierSelection < ApplicationRecord
  belongs_to :rfq_auto_analysis
  belongs_to :supplier, optional: true
  belongs_to :selected_by_user, class_name: "User", foreign_key: :selected_by_user_id

  validates :item_idx, presence: true
  validates :supplier_name, presence: true

  scope :recent, -> { order("rfq_auto_supplier_selections.created_at DESC") }
  scope :emailed, -> { where.not(emailed_at: nil) }
  scope :pending_email, -> { where(emailed_at: nil) }

  def emailed?
    emailed_at.present?
  end
end
